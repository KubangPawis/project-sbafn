from concurrent.futures import ThreadPoolExecutor, as_completed
from dotenv import load_dotenv
from pathlib import Path
import csv
import math
import time
import os

from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
import requests
import yaml

# -----------------------

REPO_ROOT = Path(__file__).resolve().parents[1]
PIPELINE_DIR = REPO_ROOT / "pipeline"

load_dotenv()
with open(PIPELINE_DIR / "configs" / "config.yaml", "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

# -----------------------

URL = "https://graph.mapillary.com/images"

# CONFIGS: MAPILLARY API - IMAGE RETRIEVAL
FIELDS = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("fields", {})
FALLBACK_FIELDS = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("fallback_fields", {})
PER_CELL_LIMIT = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("per_cell_limit", 2000)
CELL_SIZE_M = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("cell_size_m", 3000)
CELL_OVERLAP_M = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("cell_overlap_m", 100)

# CONFIGS: MAPILLARY API - MANIFEST EXPORT
MANIFEST_REPO_FIELDS = cfg.get("mapillary_api", {}).get("manifest", {}).get("repo_fields", {})

# CONFIGS: AOI
AOI_BBOX = {
    "west": cfg.get("aoi", {}).get("bbox", {}).get("west", 0),
    "south": cfg.get("aoi", {}).get("bbox", {}).get("south", 0),
    "east": cfg.get("aoi", {}).get("bbox", {}).get("east", 0),
    "north": cfg.get("aoi", {}).get("bbox", {}).get("north", 0)
}

TOKEN = os.getenv("MAPILLARY_TOKEN")
if not TOKEN:
    raise RuntimeError("Missing MAPILLARY_TOKEN. Set it in .env or the environment.")

# -----------------------

def make_session(token: str,
                 timeout: tuple[int, int] = (5, 30),
                 retries: int = 5,
                 backoff: float = 0.5) -> requests.Session:
    """
    Create a configured Session:
      - Authorization header once
      - Retry on 429/5xx
      - Store a default timeout on the session object
    """
    s = requests.Session()
    s.headers.update({"Authorization": f"OAuth {token}"})
    retry = Retry(
        total=retries,
        backoff_factor=backoff,
        status_forcelist=[429, 502, 503, 504],
        allowed_methods=frozenset({"GET"}),
        raise_on_status=False,
    )
    s.mount("https://", HTTPAdapter(max_retries=retry))

    # DATA RETRIEVAL TIMEOUT
    s.request_timeout = timeout
    return s

def get_mapillary_images(session: requests.Session,
                        bbox: dict,
                        fields: str,
                        per_cell_limit: int = 2000,
                        cell_size_m: int = 3000,
                        cell_overlap_m: int = 100) -> list[dict]:
    """
    Iterate over the general bbox (Manila, Philippines) in smaller cells to fetch Mapillary images.
    Fetch `per_cell_limit` images for each cell (dict with west/south/east/north).
    Returns: list[dict] of image metadata.
    """
    results = []
    unique_ids = set()

    base_params = {
        "bbox": f"{bbox['west']},{bbox['south']},{bbox['east']},{bbox['north']}",
        "fields": ",".join(fields),
        "limit": per_cell_limit,
    }

    url = URL
    cells = _grid_bboxes_by_meters(bbox, cell_m=cell_size_m, overlap_m=cell_overlap_m)
    #cells = cells[:5]  # LIMIT TO FIRST N CELLS FOR TESTING

    for i, cell in enumerate(cells):
        print(f"\nFetching cell {i+1}/{len(cells)}: {cell}")
        params = base_params.copy()
        params["bbox"] = f"{cell['west']},{cell['south']},{cell['east']},{cell['north']}"
        response = session.get(url, params=params, timeout=getattr(session, "request_timeout", (5, 30)))

        if response.status_code == 400 and "Unsupported get request" in response.text:
            
            # Fallback (if computed_geometry not supported): use geometry field instead
            params["fields"] = ",".join(FALLBACK_FIELDS)
            response = session.get(url, params=params, timeout=getattr(session, "request_timeout", (5, 30)))
    
        response.raise_for_status()
        
        cell_data_json = response.json()
        items = cell_data_json.get("data", []) or []
        print(f"\n[CELL {i+1}] Fetched Images: {len(items)}\n")

        # Get unique image ids only + filter for "perspective" camera type
        for i in items:
            
            # Unique ID check
            iid = i.get("id")
            if (not iid) or (iid in unique_ids):
                continue

            # Camera type check
            camera_type = (i.get("camera_type") or "").strip().lower()
            if camera_type != "perspective":
                continue

            unique_ids.add(iid)
            results.append(i)

        time.sleep(0.2)

    print(f"\n[TOTAL] Fetched Images: {len(results)}\n")
    return results

def download_thumbnails(items: list[dict],
                        session: requests.Session,
                        out_dir: str | Path,
                        max_workers: int = 8,
                        sleep_between: float = 0.02,
                        manifest_csv: str | Path | None = None):
    """
    Downloads thumbnails to `out_dir`.
    Returns list of manifest(metadata) per image record and export them to a csv file.
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rows: list[dict] = []

    def task(it):
        row = _download_one(session, it, out_dir)
        if sleep_between:
            time.sleep(sleep_between)
        return row

    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = [ex.submit(task, it) for it in items]
        for fut in as_completed(futures):
            row = fut.result()
            if row:
                rows.append(row)

    # Write manifest csv file for Label Studio
    if manifest_csv:
        _write_manifest_csv(rows, Path(manifest_csv))

    return rows

#  ------------- UTILITY FUNCTIONS -------------

def _grid_bboxes_by_meters(bbox: dict, cell_m: int = 3000, overlap_m: int = 100):
    """
    Split a bbox into ~square cells of ~cell_m meters on a side, with a small overlap.
    bbox = {"west":..., "south":..., "east":..., "north":...}
    Returns: list[dict] of {"west","south","east","north"} cells.
    """
    minlon, minlat = bbox["west"], bbox["south"]
    maxlon, maxlat = bbox["east"], bbox["north"]

    # meters → degrees at this latitude
    mid_lat = (minlat + maxlat) / 2.0
    m_per_deg_lat = 111_320.0
    m_per_deg_lon = 111_320.0 * math.cos(math.radians(mid_lat))

    dlat = cell_m / m_per_deg_lat
    dlon = cell_m / m_per_deg_lon
    olat = overlap_m / m_per_deg_lat
    olon = overlap_m / m_per_deg_lon

    cells = []
    lat = minlat
    while lat < maxlat:
        top = min(lat + dlat, maxlat)
        lon = minlon
        while lon < maxlon:
            right = min(lon + dlon, maxlon)
            cells.append({
                "west":  max(minlon, lon - olon),
                "south": max(minlat, lat - olat),
                "east":  min(maxlon, right + olon),
                "north": min(maxlat, top + olat),
            })
            lon = right
        lat = top
    return cells

def _pick_ext(resp: requests.Response, url: str) -> str:
    ctype = resp.headers.get("Content-Type", "").lower()
    if "png" in ctype:  return ".png"
    if "jpeg" in ctype or "jpg" in ctype: return ".jpg"
    if "webp" in ctype: return ".webp"
    ext = os.path.splitext(url.split("?",1)[0])[1].lower()
    if ext in {".jpg", ".jpeg", ".png", ".webp"}:
        return ext
    return ".jpg"

def _download_one(session: requests.Session, img_data: dict, out_dir: Path, timeout=(5, 60)) -> dict | None:
    iid = img_data.get("id")
    if not iid:
        return None

    # Build download candidates in priority order (2048 → 1024)
    thumb_2048 = img_data.get("thumb_2048_url")
    thumb_1024 = img_data.get("thumb_1024_url")
    candidates = [u for u in (thumb_2048, thumb_1024) if u]

    for url in candidates:
        try:
            resp = session.get(url, stream=True, timeout=timeout)
            resp.raise_for_status()
            ext = _pick_ext(resp, url)
            kind = "2048" if url is thumb_2048 else "1024"
            out_path = out_dir / f"{iid}_{kind}{ext}"

            if out_path.exists():
                resp.close()
                return {
                    "id": iid,
                    "file_path": str(out_path),
                    "thumb_kind": kind,
                    "captured_at": img_data.get("captured_at"),
                    "camera_type": img_data.get("camera_type"),
                    "sequence": img_data.get("sequence"),
                    "lat": (img_data.get("computed_geometry") or {}).get("coordinates", [None, None])[1]
                           if img_data.get("computed_geometry")
                           else (img_data.get("geometry") or {}).get("coordinates", [None, None])[1],
                    "lon": (img_data.get("computed_geometry") or {}).get("coordinates", [None, None])[0]
                           if img_data.get("computed_geometry")
                           else (img_data.get("geometry") or {}).get("coordinates", [None, None])[0],
                    "width": img_data.get("width"),
                    "height": img_data.get("height"),
                }

            tmp = out_path.with_suffix(out_path.suffix + ".part")
            tmp.parent.mkdir(parents=True, exist_ok=True)
            with open(tmp, "wb") as f:
                for chunk in resp.iter_content(1 << 15):
                    if chunk:
                        f.write(chunk)
            tmp.replace(out_path)
            resp.close()

            return {
                "id": iid,
                "file_path": str(out_path),
                "thumb_kind": kind,
                "captured_at": img_data.get("captured_at"),
                "camera_type": img_data.get("camera_type"),
                "sequence": img_data.get("sequence"),
                "lat": (img_data.get("computed_geometry") or {}).get("coordinates", [None, None])[1]
                       if img_data.get("computed_geometry")
                       else (img_data.get("geometry") or {}).get("coordinates", [None, None])[1],
                "lon": (img_data.get("computed_geometry") or {}).get("coordinates", [None, None])[0]
                       if img_data.get("computed_geometry")
                       else (img_data.get("geometry") or {}).get("coordinates", [None, None])[0],
                "width": img_data.get("width"),
                "height": img_data.get("height"),
            }
        except requests.RequestException:
            continue

    print(f"[!] Failed to download image {iid}: no working thumbnail")
    return None

def _write_manifest_csv(rows: list[dict], manifest_outdir: Path):
    manifest_outdir.parent.mkdir(parents=True, exist_ok=True)

    # Fields for the REPO copy (no file_path)
    repo_fields = MANIFEST_REPO_FIELDS

    # Fields for the LOCAL copy (with file_path for annotation tools)
    local_fields = repo_fields + ["file_path"]

    # [REPO COPY] Tracked for reproducibility purposes
    with open(manifest_outdir / "mapillary_manifest.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=repo_fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in repo_fields})

    # [LOCAL COPY] gitignored; Used for Label Studio import
    with open(manifest_outdir / "mapillary_manifest_local.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=local_fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in local_fields})

#  ---------------------------------------

if __name__ == "__main__":

    # [IMAGE METADATA FETCH] Get Mapillary image metadata within AOI
    session = make_session(TOKEN, timeout=(5, 30))
    imgs = get_mapillary_images(session=session, bbox=AOI_BBOX, fields=FIELDS, per_cell_limit=PER_CELL_LIMIT, cell_size_m=CELL_SIZE_M, cell_overlap_m=CELL_OVERLAP_M)

    # [IMAGE DOWNLOAD] Download Mapillary images locally
    images_outdir = REPO_ROOT / "data" / "images"
    manifest_outdir = REPO_ROOT / "data" / "meta"
    images_outdir.mkdir(parents=True, exist_ok=True)
    manifest_outdir.mkdir(parents=True, exist_ok=True)
    download_thumbnails(imgs, session, out_dir=images_outdir, max_workers=4, manifest_csv= manifest_outdir)