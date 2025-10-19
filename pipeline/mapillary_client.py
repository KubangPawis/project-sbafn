from dotenv import load_dotenv
from pathlib import Path
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
                        per_cell_limit: int = 2000,
                        cell_size_m: int = 3000,
                        cell_overlap_m: int = 100,
                        fields: str = "id,width,height,camera_type,creator_username,captured_at,thumb_1024_url,thumb_2048_url,computed_geometry"):
    """
    Iterate over the general bbox (Manila, Philippines) in smaller cells to fetch Mapillary images.
    Fetch `per_cell_limit` images for each cell (dict with west/south/east/north).
    Returns: list[dict] of image metadata.
    """
    results = []
    unique_ids = set()

    base_params = {
        "bbox": f"{bbox['west']},{bbox['south']},{bbox['east']},{bbox['north']}",
        "fields": fields,
        "limit": per_cell_limit,
    }

    url = URL
    cells = grid_bboxes_by_meters(bbox, cell_m=cell_size_m, overlap_m=cell_overlap_m)
    #cells = cells[:5]  # LIMIT TO FIRST 5 CELLS FOR TESTING

    for i, cell in enumerate(cells):
        print(f"\nFetching cell {i+1}/{len(cells)}: {cell}")
        params = base_params.copy()
        params["bbox"] = f"{cell['west']},{cell['south']},{cell['east']},{cell['north']}"
        response = session.get(url, params=params, timeout=getattr(session, "request_timeout", (5, 30)))

        if response.status_code == 400 and "Unsupported get request" in response.text:
            params["fields"] = (
                "id,width,height,camera_type,creator_username,captured_at,thumb_1024_url,thumb_2048_url,geometry"
            )
            response = session.get(url, params=params, timeout=getattr(session, "request_timeout", (5, 30)))
    
        response.raise_for_status()
        
        cell_data_json = response.json()
        items = cell_data_json.get("data", []) or []

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

            # Pick thumbnail URL (2048px preferred)
            thumb_2048 = i.get("thumb_2048_url")
            thumb_1024 = i.get("thumb_1024_url")
            thumb = thumb_2048 or thumb_1024
            if not thumb:
                continue

            i["thumb_url"] = thumb
            i["thumb_kind"] = "2048" if thumb_2048 else "1024"

            unique_ids.add(iid)
            results.append(i)

        time.sleep(0.2)

    print(f"\nFetched Total Images: {len(results)}\n")
    return results

def grid_bboxes_by_meters(bbox: dict, cell_m: int = 3000, overlap_m: int = 100):
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
    
if __name__ == "__main__":
    session = make_session(TOKEN, timeout=(5, 30))
    imgs = get_mapillary_images(session, AOI_BBOX, per_cell_limit=5, cell_size_m=1000, cell_overlap_m=100)
    print()
    print(imgs)