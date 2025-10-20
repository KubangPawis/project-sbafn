import numpy as np, rasterio, math, pandas as pd
from rasterio.merge import merge
from rasterio.transform import rowcol
import requests
from shapely.geometry import shape, Point

# ---- Edit bbox (tight City of Manila) ----
MIN_LON, MIN_LAT = 120.95, 14.55
MAX_LON, MAX_LAT = 121.03, 14.65

# ---- Open BOTH tiles (Manila straddles 120E–121E) ----
tile1 = "data/Copernicus_DSM_COG_10_N14_00_E120_00_DEM.tif"
tile2 = "data/Copernicus_DSM_COG_10_N14_00_E121_00_DEM.tif"

with rasterio.open(tile1) as s1, rasterio.open(tile2) as s2:
    mosaic, T = merge([s1, s2])              # mosaic[0, r, c], T is transform
    # Compute row/col window for bbox (note: y uses MAX_LAT at top)
    r0, c0 = rowcol(T, MIN_LON, MAX_LAT, op=math.floor)  # top-left
    r1, c1 = rowcol(T, MAX_LON, MIN_LAT, op=math.ceil)   # bottom-right

    # Clamp to raster bounds
    r0 = max(0, min(r0, mosaic.shape[1])); r1 = max(0, min(r1, mosaic.shape[1]))
    c0 = max(0, min(c0, mosaic.shape[2])); c1 = max(0, min(c1, mosaic.shape[2]))

    # Build pixel-aligned coordinate arrays (centers)
    # Affine: x = a*col + c, y = e*row + f   (a>0, e<0 for north-up)
    a, b, c, d, e, f = T.a, T.b, T.c, T.d, T.e, T.f
    cols = np.arange(c0, c1)
    rows = np.arange(r0, r1)
    lons = c + (cols + 0.5)*a                              # 1D
    lats = f + (rows + 0.5)*e                              # 1D (e<0)
    LON = np.tile(lons, (len(rows), 1))                    # 2D
    LAT = np.tile(lats.reshape(-1,1), (1, len(cols)))      # 2D

    # Extract DEM patch
    patch = mosaic[0, r0:r1, c0:c1].astype("float32")

# Flatten & export
out = pd.DataFrame({
    "lat": LAT.ravel(),
    "lon": LON.ravel(),
    "elevation_30m": patch.ravel()
}).dropna(subset=["elevation_30m"]).reset_index(drop=True)

out.to_csv("data/manila_city_30m_grid.csv", index=False)
print("Wrote manila_city_30m_grid.csv with", len(out), "rows",
      "(~{}x{} grid)".format(len(rows), len(cols)))

r = requests.get("https://nominatim.openstreetmap.org/search",
                 params={"city":"Manila","country":"Philippines","format":"jsonv2","polygon_geojson":1},
                 headers={"User-Agent":"manila-grid"}).json()
poly = shape(max(r, key=lambda x: x.get("importance",0))["geojson"])

mask = [poly.contains(Point(lon, lat)) for lat, lon in zip(out["lat"], out["lon"])]
city = out[mask].reset_index(drop=True)
city.to_csv("data/manila_city_30m_grid_cityonly.csv", index=False)
print("City-only rows:", len(city))
