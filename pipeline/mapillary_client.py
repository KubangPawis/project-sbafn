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
import cv2
import numpy as np

# -----------------------

REPO_ROOT = Path(__file__).resolve().parents[1]
PIPELINE_DIR = REPO_ROOT / "pipeline"

load_dotenv()
with open(PIPELINE_DIR / "configs" / "config.yaml", "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

# -----------------------

URL = "https://graph.mapillary.com/images"

# CONFIGS: MAPILLARY API - IMAGE RETRIEVAL
RETRIEVED_IMAGES_OUT_DIR = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("out_dir", "data/images/")
FIELDS = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("fields", {})
FALLBACK_FIELDS = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("fallback_fields", {})
PER_CELL_LIMIT = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("per_cell_limit", 2000)
CELL_SIZE_M = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("cell_size_m", 3000)
CELL_OVERLAP_M = cfg.get("mapillary_api", {}).get("image_retrieval", {}).get("cell_overlap_m", 100)

# CONFIGS: MAPILLARY API - MANIFEST EXPORT
MANIFEST_REPO_FIELDS = cfg.get("mapillary_api", {}).get("manifest", {}).get("repo_fields", {})
MANIFEST_OUT_DIR = cfg.get("mapillary_api", {}).get("manifest", {}).get("out_dir", "data/meta/")
MANIFEST_REPO_NAME = cfg.get("mapillary_api", {}).get("manifest", {}).get("repo_manifest_name", "mapillary_manifest.csv")
MANIFEST_LOCAL_NAME = cfg.get("mapillary_api", {}).get("manifest", {}).get("local_manifest_name", "mapillary_manifest_local.csv")

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
        #"limit": per_cell_limit,
    }

    url = URL
    cells = _grid_bboxes_by_meters(bbox, cell_m=cell_size_m, overlap_m=cell_overlap_m)
    #cells = cells[:5]  # LIMIT TO FIRST N CELLS FOR TESTING

    # [DIAGNOSTIC INFO] Check if the grid splitting is as expected
    diag_results = _diag_grid(bbox, cell_size_m)
    print(f"\n[DIAGNOSIS]\nExpected Cells: {diag_results['expected_cells']}")
    print("Actual Cells:", len(cells))

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

            unique_ids.add(iid)
            results.append(i)

        time.sleep(0.2)

    print(f"\n[TOTAL] Fetched Images: {len(results)}\n")
    return results

def download_thumbnails(items: list[dict],
                        session: requests.Session,
                        out_dir: str | Path,
                        manifest_repo_name: str,
                        manifest_local_name: str,
                        max_workers: int = 8,
                        sleep_between: float = 0.02,
                        manifest_csv: str | Path | None = None,
                        ) -> list[dict]:
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
            if not row:
                continue
            # PANORAMA
            if isinstance(row, list):
                rows.extend(row)
            # PERSPECTIVE / FISHEYE
            else:
                rows.append(row)

    # Write manifest csv file for Label Studio
    if manifest_csv:
        _write_manifest_csv(rows=rows, 
                            manifest_outdir=Path(manifest_csv), 
                            manifest_repo_name=manifest_repo_name, 
                            manifest_local_name=manifest_local_name
                            )

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

def _download_one(session: requests.Session, img_data: dict, out_dir: Path, timeout=(5, 60)) -> dict | list[dict] | None:
    iid = img_data.get("id")
    if not iid:
        return None

    camera_type = (img_data.get("camera_type") or "").strip().lower()
    is_pano = bool(img_data.get("is_pano"))
    is_spherical = is_pano or camera_type in {"spherical", "equirectangular"}

    # Common metadata helpers
    def _row(file_path: Path, extra: dict) -> dict:
        lat = (img_data.get("computed_geometry") or {}).get("coordinates", [None, None])[1] \
              if img_data.get("computed_geometry") \
              else (img_data.get("geometry") or {}).get("coordinates", [None, None])[1]
        lon = (img_data.get("computed_geometry") or {}).get("coordinates", [None, None])[0] \
              if img_data.get("computed_geometry") \
              else (img_data.get("geometry") or {}).get("coordinates", [None, None])[0]
        base = {
            "id": iid,
            "thumb_kind": extra.get("thumb_kind"),
            "file_path": str(file_path),
            "captured_at": img_data.get("captured_at"),
            "camera_type": img_data.get("camera_type"),
            "sequence": img_data.get("sequence"),
            "lat": lat, 
            "lon": lon,
            "width": img_data.get("width"),
            "height": img_data.get("height"),
            "face": (extra.get("face") or ""),
            "yaw_deg": (extra.get("yaw_deg") or ""),
            "pitch_deg": (extra.get("pitch_deg") or ""),
            "hfov_deg": (extra.get("hfov_deg") or ""),
        }
        base.update(extra)
        return base
    
    thumb_2048 = img_data.get("thumb_2048_url")
    thumb_1024 = img_data.get("thumb_1024_url")
    

    # -------- 360 PANORAMAS: render left/forward/right ----------
    if is_spherical:
        url = thumb_2048 or thumb_1024
        if not url:
            print(f"[!] Pano {iid} missing thumb URL")
            return None

        try:
            kind = "2048" if (url == thumb_2048) else "1024"
            resp = session.get(url, stream=True, timeout=timeout)
            resp.raise_for_status()
            data = np.frombuffer(resp.content, dtype=np.uint8)
            pano = cv2.imdecode(data, cv2.IMREAD_COLOR)
            resp.close()
        finally:
            try: resp.close()
            except: pass

        if pano is None:
            print(f"[!] Failed to decode pano {iid}")
            return None

        # Heading (degrees). If missing, assume 0.
        yaw0 = img_data.get("compass_angle")
        try:
            yaw0 = float(yaw0) if yaw0 is not None else 0.0
        except (ValueError, TypeError):
            yaw0 = 0.0

        faces = [
            ("left",    yaw0 - 90.0),
            ("forward", yaw0 + 0.0),
            ("right",   yaw0 + 90.0),
        ]
        hfov = 80.0
        pitch = -10.0
        out_w, out_h = 1024, 1024

        rows: list[dict] = []
        for face_name, yaw in faces:
            try:
                view = _equirect_to_perspective(pano, yaw_deg=yaw, pitch_deg=pitch, hfov_deg=hfov, out_w=out_w, out_h=out_h)
                out_path = out_dir / f"{iid}_{face_name}.jpg"
                cv2.imwrite(str(out_path), view)
                rows.append(_row(out_path, {
                    "thumb_kind": kind,
                    "face": face_name,
                    "yaw_deg": yaw,
                    "pitch_deg": pitch,
                    "hfov_deg": hfov,
                    "width": out_w,
                    "height": out_h
                }))
            except Exception as e:
                print(f"[!] Failed pano face {face_name} for {iid}: {e}")
                continue

        if not rows:
            return None
        return rows

    # -------- PERSPECTIVE ----------
    
    candidates = [u for u in (thumb_2048, thumb_1024) if u]
    for url in candidates:
        try:
            resp = session.get(url, timeout=timeout)
            resp.raise_for_status()
            ext = _pick_ext(resp, url)
            kind = "2048" if (url == thumb_2048) else "1024"
            out_path = out_dir / f"{iid}_{kind}{ext}"

            if out_path.exists():
                resp.close()
                return _row(out_path, {"thumb_kind": kind})

            tmp = out_path.with_suffix(out_path.suffix + ".part")
            tmp.parent.mkdir(parents=True, exist_ok=True)
            with open(tmp, "wb") as f:
                for chunk in resp.iter_content(1 << 15):
                    if chunk:
                        f.write(chunk)
            tmp.replace(out_path)
            resp.close()

            return _row(out_path, {"thumb_kind": kind})
        except requests.RequestException:
            continue

    print(f"[!] Failed to download image {iid}: no working thumbnail")
    return None

def _write_manifest_csv(rows: list[dict], manifest_outdir: Path, manifest_repo_name: str, manifest_local_name: str):
    manifest_outdir.parent.mkdir(parents=True, exist_ok=True)

    # Fields for the REPO copy (no file_path)
    repo_fields = MANIFEST_REPO_FIELDS

    # Fields for the LOCAL copy (with file_path for annotation tools)
    local_fields = repo_fields + ["file_path"]

    # [REPO COPY] Tracked for reproducibility purposes
    with open(manifest_outdir / manifest_repo_name, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=repo_fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in repo_fields})

    # [LOCAL COPY] gitignored; Used for Label Studio import
    with open(manifest_outdir / manifest_local_name, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=local_fields, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k) for k in local_fields})

def _diag_grid(bbox, cell_m):
    minlon, minlat = bbox["west"], bbox["south"]
    maxlon, maxlat = bbox["east"], bbox["north"]
    mid_lat = (minlat + maxlat) / 2.0
    m_per_deg_lat = 111_320.0
    m_per_deg_lon = 111_320.0 * math.cos(math.radians(mid_lat))
    dlat = cell_m / m_per_deg_lat
    dlon = cell_m / m_per_deg_lon
    n_rows = math.ceil((maxlat - minlat) / dlat)
    n_cols = math.ceil((maxlon - minlon) / dlon)
    res = {
        "cell_m": cell_m,
        "AOI_dlat_deg": maxlat - minlat,
        "AOI_dlon_deg": maxlon - minlon,
        "step_dlat_deg": dlat,
        "step_dlon_deg": dlon,
        "expected_rows": n_rows,
        "expected_cols": n_cols,
        "expected_cells": n_rows * n_cols,
    }
    return res

def _equirect_to_perspective(pano_bgr, yaw_deg=0.0, pitch_deg=0.0, hfov_deg=90.0, out_w=1024, out_h=1024):
    """
    pano_bgr: HxWx3 equirectangular image (BGR)
    yaw_deg, pitch_deg: camera orientation (degrees), yaw: +CW from North if using compass; here we treat +yaw as to the right
    hfov_deg: horizontal field of view of virtual camera
    out_w, out_h: output size
    """
    H, W = pano_bgr.shape[:2]
    hfov = math.radians(hfov_deg)
    f = 0.5 * out_w / math.tan(hfov * 0.5)
    cx, cy = (out_w - 1) / 2.0, (out_h - 1) / 2.0

    # Pixel grid in camera coordinates (z forward)
    x = (np.arange(out_w) - cx) / f
    y = -(np.arange(out_h) - cy) / f
    xx, yy = np.meshgrid(x, y)
    zz = np.ones_like(xx)

    # Normalize camera rays
    inv_norm = 1.0 / np.sqrt(xx*xx + yy*yy + zz*zz)
    xr, yr, zr = xx*inv_norm, yy*inv_norm, zz*inv_norm

    # Rotation (yaw about +Y, pitch about +X) – right-handed, z forward
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    cyaw, syaw = math.cos(yaw), math.sin(yaw)
    cpit, spit = math.cos(pitch), math.sin(pitch)

    # R = R_yaw * R_pitch
    x1 =  cyaw * xr + 0 * yr + syaw * zr
    y1 =  spit * (syaw * xr) + cpit * yr - spit * (cyaw * zr)
    z1 = -cpit * (syaw * xr) + spit * yr + cpit * (cyaw * zr)

    # to spherical (θ in [-π, π], φ in [-π/2, π/2])
    theta = np.arctan2(x1, z1)          # yaw
    phi   = np.arcsin(np.clip(y1, -1, 1))  # pitch

    # Map to pano coords
    u = (theta / (2*np.pi) + 0.5) * W
    v = (0.5 - phi / np.pi) * H

    # Remap – wrap horizontally, clamp vertically
    map_x = u.astype(np.float32)
    map_y = np.clip(v, 0, H-1).astype(np.float32)
    view = cv2.remap(pano_bgr, map_x, map_y, interpolation=cv2.INTER_LINEAR,
                     borderMode=cv2.BORDER_WRAP)
    return view

#  ---------------------------------------

if __name__ == "__main__":

    # [IMAGE METADATA FETCH] Get Mapillary image metadata within AOI
    session = make_session(TOKEN, timeout=(5, 30))
    imgs = get_mapillary_images(session=session, bbox=AOI_BBOX, fields=FIELDS, per_cell_limit=PER_CELL_LIMIT, cell_size_m=CELL_SIZE_M, cell_overlap_m=CELL_OVERLAP_M)

    # [IMAGE DOWNLOAD] Download Mapillary images locally
    images_outdir = REPO_ROOT / RETRIEVED_IMAGES_OUT_DIR
    manifest_outdir = REPO_ROOT / MANIFEST_OUT_DIR
    manifest_repo_name = MANIFEST_REPO_NAME
    manifest_local_name = MANIFEST_LOCAL_NAME

    images_outdir.mkdir(parents=True, exist_ok=True)
    manifest_outdir.mkdir(parents=True, exist_ok=True)

    download_thumbnails(imgs, 
                        session, 
                        out_dir=images_outdir, 
                        manifest_repo_name=manifest_repo_name, 
                        manifest_local_name=manifest_local_name, 
                        max_workers=4, 
                        manifest_csv= manifest_outdir
                        )