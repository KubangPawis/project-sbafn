from shapely.geometry import shape, mapping
from pathlib import Path

from botocore.config import Config
from botocore import UNSIGNED
from rasterio.features import geometry_mask
from rasterio.merge import merge
import pandas as pd
import numpy as np
import boto3
import rasterio
import requests
import yaml

# --------------------

REPO_ROOT = Path(__file__).resolve().parents[2]

with open(REPO_ROOT / "pipeline" / "configs" / "config.yaml", "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

# CONFIGS: Elevation
CACHE_DIR = Path(cfg.get("elevation", {}).get("cache_dir", ""))
TILES = cfg.get("elevation", {}).get("tiles", [])
OUT_DIR = cfg.get("elevation", {}).get("out_dir", "")

# CONFIGS: AOI
AOI_PLACE_NAME = cfg.get("aoi", {}).get("place_name")
AOI_AREA_NAME = cfg.get("aoi", {}).get("area_name")
AOI_ABBR = cfg.get("aoi", {}).get("abbr")
MIN_LON = cfg.get("aoi", {}).get("bbox", {}).get("west", 0)
MIN_LAT = cfg.get("aoi", {}).get("bbox", {}).get("south", 0)
MAX_LON = cfg.get("aoi", {}).get("bbox", {}).get("east", 0)
MAX_LAT = cfg.get("aoi", {}).get("bbox", {}).get("north", 0)
bounds = (MIN_LON, MIN_LAT, MAX_LON, MAX_LAT)

# --------------------

def s3_to_https(s3_uri: str) -> str:
    return s3_uri.replace("s3://copernicus-dem-30m/",
                          "https://copernicus-dem-30m.s3.amazonaws.com/")

def ensure_local(s3_uri: str) -> Path:
    assert CACHE_DIR is not None, "CACHE_DIR must be set to download"
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    fname = Path(s3_uri.split("/")[-1])
    out = CACHE_DIR / fname
    if out.exists():
        return out
    
    # AWS S3: Unsigned client for data access
    bucket = "copernicus-dem-30m"
    key = s3_uri.split(bucket + "/")[1]
    s3 = boto3.client("s3", config=Config(signature_version=UNSIGNED))
    tmp = out.with_suffix(out.suffix + ".part")
    s3.download_file(bucket, key, str(tmp))
    tmp.replace(out)
    return out

def open_sources():
    if CACHE_DIR:
        paths = [str(ensure_local(u)) for u in TILES]
    else:
        paths = [s3_to_https(u) for u in TILES]
    env = rasterio.Env(
        GDAL_DISABLE_READDIR_ON_OPEN="YES",
        GDAL_HTTP_MAX_RETRY="5",
        GDAL_HTTP_RETRY_DELAY="0.5",
        CPL_VSIL_CURL_CACHE_SIZE="20000000",
    )
    return env, [rasterio.open(p) for p in paths]

def grid_lonlat(transform, H, W):
    a, b, c, d, e, f = transform.a, transform.b, transform.c, transform.d, transform.e, transform.f
    cols = np.arange(W); rows = np.arange(H)
    lons = c + (cols + 0.5)*a
    lats = f + (rows + 0.5)*e
    LON = np.tile(lons, (H, 1))
    LAT = np.tile(lats.reshape(-1,1), (1, W))
    return LAT, LON

def fetch_city_polygon(city, country):
    r = requests.get(
        "https://nominatim.openstreetmap.org/search",
        params={"city": city, "country": country, "format": "jsonv2", "polygon_geojson": 1},
        headers={"User-Agent": "sbafn-elev/0.1 (contact@example.com)"},
        timeout=30
    ).json()
    return shape(max(r, key=lambda x: x.get("importance", 0))["geojson"])

# --------------------

def fetch_elevation():
    env, srcs = open_sources()
    try:
        with env:
            # Mosaic AND crop to bbox in one go
            mosaic, transform = merge(srcs, bounds=bounds)
            data = mosaic[0].astype("float32")

            for s in srcs:
                if s.nodata is not None:
                    data = np.where(data == s.nodata, np.nan, data)
    finally:
        for s in srcs:
            s.close()

    H, W = data.shape
    LAT, LON = grid_lonlat(transform, H, W)

    # City mask (vectorized)
    city_poly = fetch_city_polygon(AOI_AREA_NAME, "Philippines")
    mask = geometry_mask([mapping(city_poly)], out_shape=(H, W), transform=transform, invert=True)
    data_city = np.where(mask, data, np.nan)

    # [EXPORT] Output filtered elevation file (only AOI)
    df_city = pd.DataFrame({
        "lat": LAT.ravel(),
        "lon": LON.ravel(),
        "elevation_30m": data_city.ravel()
    }).dropna(subset=["elevation_30m"]).reset_index(drop=True)
    df_city.to_csv(REPO_ROOT / OUT_DIR / f"{AOI_ABBR}_30m_grid.csv", index=False)

    print(f"[DONE] Wrote {AOI_PLACE_NAME} elevation data")
    print("[DONE] City-only rows:", len(df_city))

if __name__ == "__main__":
    fetch_elevation()