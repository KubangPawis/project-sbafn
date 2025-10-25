# rainfall_pipeline.py
import xarray as xr
import numpy as np
import pandas as pd
from datetime import datetime
import earthaccess
from tqdm import tqdm
import os
import re

# === CONFIG ===
LAT_MIN, LAT_MAX = 14.45, 14.75
LON_MIN, LON_MAX = 120.8, 121.2
START_DATE, END_DATE = "2025-05-01", "2025-10-22"
DATA_DIR = "./data/imerg_data_dl"
OUTPUT_FILE = "./data/rainfall_daily_features.csv"

os.makedirs(DATA_DIR, exist_ok=True)

# === LOGIN ===
auth = earthaccess.login()
print("🔐 Logged in successfully")

# === SEARCH IMERGDL DAILY ===
results = earthaccess.search_data(
    short_name="GPM_3IMERGDL",
    version="07",
    temporal=(START_DATE, END_DATE),
    bounding_box=(LON_MIN, LAT_MIN, LON_MAX, LAT_MAX),
)
print(f"🌧 Found {len(results)} IMERGDL daily granules")

# === DOWNLOAD ===
downloaded_files = []
for granule in tqdm(results, desc="📥 Downloading IMERGDL"):
    urls = granule.data_links(access="https")
    if not urls:
        continue
    url = urls[0]
    fname = os.path.basename(url)
    local_path = os.path.join(DATA_DIR, fname)

    if os.path.exists(local_path):
        print(f"⏩ Skipping existing file: {fname}")
        downloaded_files.append(local_path)
        continue

    downloaded = earthaccess.download([granule], local_path=DATA_DIR)
    if not downloaded:
        continue

    downloaded_files.append(downloaded[0])

print(f"📦 Total ready: {len(downloaded_files)}")

# === EXTRACT RAINFALL ===
rows = []
for file_path in tqdm(downloaded_files, desc="🌧 Extracting precipitation"):
    fname = os.path.basename(file_path)
    try:
        ds = xr.open_dataset(file_path, engine="netcdf4")
        if "precipitation" not in ds:
            continue

        rain = ds["precipitation"]

        if rain.dims.index("lon") < rain.dims.index("lat"):
            subset = rain.sel(lon=slice(LON_MIN, LON_MAX), lat=slice(LAT_MIN, LAT_MAX))
        else:
            subset = rain.sel(lat=slice(LAT_MAX, LAT_MIN), lon=slice(LON_MIN, LON_MAX))

        mean_rain = float(np.nanmean(subset.values))
        if np.isnan(mean_rain):
            continue

        match = re.search(r"(\d{8})-S\d{6}", fname)
        if match:
            date = datetime.strptime(match.group(1), "%Y%m%d")
        else:
            continue

        rows.append({"date": date, "rain_intensity_mmday": mean_rain})
    except Exception as e:
        print(f"⚠️ {fname}: {e}")
        continue

# === BUILD DATAFRAME ===
df = pd.DataFrame(rows).sort_values("date")
if not df.empty:
    for days in [1, 3, 7, 14, 30]:
        df[f"r_{days}d"] = df["rain_intensity_mmday"].rolling(window=days, min_periods=1).sum()

    df.to_csv(OUTPUT_FILE, index=False)
    print(f"✅ Saved rainfall data → {OUTPUT_FILE}")
else:
    print("⚠️ No rainfall data extracted.")
