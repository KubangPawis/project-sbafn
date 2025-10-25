# news_match_pipeline.py (robust + normalized matching)
import pandas as pd
import re
import os

# === File Paths ===
DATA_DIR = "/outputs"
os.makedirs(DATA_DIR, exist_ok=True)

rain_path = os.path.join(DATA_DIR, "rainfall_daily_features.csv")
news_path = os.path.join(DATA_DIR, "inquirer_flood_articles.csv")
streets_path = os.path.join(DATA_DIR, "mnl_pu_features.csv")
output_path = os.path.join(DATA_DIR, "matched_street_floods_full.csv")

# === Load Data ===
rain_df = pd.read_csv(rain_path, parse_dates=["date"])
news_df = pd.read_csv(news_path)
streets_df = pd.read_csv(streets_path)

print(f"🌧 Rainfall days: {len(rain_df)}")
print(f"📰 News articles: {len(news_df)}")
print(f"🛣️ Street segments: {len(streets_df)}")

# === Normalize street names ===
def normalize_name(name):
    if not isinstance(name, str):
        return ""
    name = name.lower()
    name = re.sub(r'\bstreet\b|\broad\b|\bavenue\b|\bave\b|\bblvd\b|\bboulevard\b|\bdr\b|\bdrive\b', '', name)
    name = re.sub(r'[^a-z0-9\s]', '', name)
    name = re.sub(r'\s+', ' ', name).strip()
    return name

streets_df["street_label_clean"] = streets_df["street_label"].apply(normalize_name)

# === Helper: Clean possible street mentions from articles ===
def clean_affected_text(text: str):
    text = re.sub(r"['\"\[\]\(\):]", " ", text)
    stopwords = [
        "deep", "inches", "gutter", "passable", "vehicles", "types", "nb", "sb",
        "half", "tire", "knee", "corner", "intersection", "infront", "front",
        "service", "road", "not", "light", "type", "all"
    ]
    tokens = re.findall(r"[A-Za-z0-9]+", text.lower())
    tokens = [t for t in tokens if t not in stopwords and len(t) > 2]
    return tokens

# === STEP 1: Extract affected street roots ===
reported_streets = set()

for _, row in news_df.iterrows():
    affected = row.get("affected_areas", "")
    if not isinstance(affected, str):
        continue

    affected_list = re.split(r"[,\n]+", affected)
    cleaned = []
    for a in affected_list:
        tokens = clean_affected_text(a)
        if tokens:
            cleaned.append(" ".join(tokens))
    reported_streets.update(cleaned)
    print(f"📰 Cleaned affected list: {cleaned}")

reported_streets = [normalize_name(s) for s in reported_streets if len(s) > 3]
print(f"📍 Total unique reported street names (normalized): {len(reported_streets)}")

# === STEP 2: Mark segments if reported ===
streets_df["s"] = streets_df["street_label_clean"].apply(
    lambda st: 1 if any(rs in st for rs in reported_streets) else 0
)
print(f"✅ Flooded (reported) segments detected: {streets_df['s'].sum()} / {len(streets_df)}")

# === STEP 3: Combine rainfall × streets ===
rain_df["key"] = 1
streets_df["key"] = 1
final_df = pd.merge(rain_df, streets_df, on="key").drop(columns=["key"])

# === STEP 4: Final formatting ===
final_cols = [
    "date", "rain_intensity_mmday", "r_1d", "r_3d", "r_7d", "r_14d", "r_30d",
    "segment_id", "elev_mean", "elev_min", "elev_p10", "elev_p90", "elev_max",
    "elev_range", "elev_start", "elev_end", "grade_pct", "n_elev_pts_used",
    "attach_method", "corridor_id", "parent_u", "parent_v", "parent_key",
    "street_label", "highway", "lanes", "length_m", "s"
]
final_df = final_df[[c for c in final_cols if c in final_df.columns]].drop_duplicates()

# === STEP 5: Filter only flooded streets (s == 1) ===
final_df = final_df[final_df["s"] == 1].reset_index(drop=True)

# === STEP 6: Save output ===
final_df.to_csv(output_path, index=False)
print(f"✅ Final dataset saved → {output_path}")
print(f"📊 Total rows: {len(final_df)} | Flooded segments: {final_df['s'].sum()}")
