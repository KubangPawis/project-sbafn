"""
Join 30 m elevation points to SBAFN segments via buffer, with centroid fallback.

Inputs
- segments: GeoJSON/GeoParquet/GeoPackage (LineString), WGS84 or any CRS
- elevation CSV: lon, lat, elev (column names are auto-detected heuristically)

Outputs
- CSV: segments with elevation features per segment
    {segment_id, corridor_id?, street_label?, length_m?,
     elev_mean, elev_min, elev_p10, elev_p90, elev_max, elev_range,
     elev_start, elev_end, grade_pct,
     n_elev_pts_used, attach_method}

Method
1) Project to EPSG:32651 (UTM 51N) for Manila so distances are meters.
2) Build a small buffer around each segment (default 15 m) and sjoin elevation points inside.
3) If no points land in the buffer, fallback: take the nearest elevation point to the segment centroid within max_nn (default 60 m).
4) For grade, sample start and end by taking the nearest elevation point to each endpoint (independent of buffer).

Usage
    python segments_elevation_join.py \
      --segments pipeline/outputs/mnl_segments.geojson \
      --elev_csv pipeline/outputs/manila_city_30m_grid_cityonly.csv \
      --out_csv pipeline/outputs/mnl_segments_with_elevation.csv

Notes
- Assumes elevation is ground elevation; bridges/tunnels are not corrected here.
- Tune --buf_m and --max_nn_m if your grid resolution differs.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Tuple

import geopandas as gpd
import pandas as pd
from shapely.geometry import Point

UTM_MNL = "EPSG:32651"  # UTM 51N
WGS84 = "EPSG:4326"

# -----------------------------
# Heuristics to detect lon/lat/elev columns in the CSV
# -----------------------------

def detect_cols(df: pd.DataFrame) -> Tuple[str, str, str]:
    cols_lower = {c.lower(): c for c in df.columns}
    # long/lon/longitude
    lon_candidates = [c for c in df.columns if c.lower() in {"lon","long","longitude","x","lng"}]
    lat_candidates = [c for c in df.columns if c.lower() in {"lat","latitude","y"}]
    elev_candidates = [c for c in df.columns if c.lower() in {"elev","elevation","z","height","dem","h"}]

    if not lon_candidates or not lat_candidates:
        # try common pairs
        if "x" in cols_lower and "y" in cols_lower:
            lon_candidates = [cols_lower["x"]]
            lat_candidates = [cols_lower["y"]]
    if not elev_candidates:
        # guess first numeric column not in lon/lat
        numeric = [c for c in df.columns if pd.api.types.is_numeric_dtype(df[c])]
        numeric = [c for c in numeric if c not in lon_candidates + lat_candidates]
        if numeric:
            elev_candidates = [numeric[0]]

    if not lon_candidates or not lat_candidates or not elev_candidates:
        raise ValueError("Could not detect lon/lat/elev columns. Pass a CSV with columns like lon,lat,elev.")

    return lon_candidates[0], lat_candidates[0], elev_candidates[0]

# -----------------------------
# Core logic
# -----------------------------

def build_elev_gdf(csv_path: Path) -> gpd.GeoDataFrame:
    df = pd.read_csv(csv_path)
    lon_col, lat_col, elev_col = detect_cols(df)
    df = df[[lon_col, lat_col, elev_col]].copy()
    df.columns = ["lon", "lat", "elev"]
    gdf = gpd.GeoDataFrame(df, geometry=gpd.points_from_xy(df["lon"], df["lat"], crs=WGS84))
    return gdf


def summarize(vals: pd.Series) -> dict:
    v = vals.dropna().astype(float)
    if v.empty:
        return {"elev_mean": None, "elev_min": None, "elev_p10": None, "elev_p90": None, "elev_max": None, "elev_range": None}
    return {
        "elev_mean": float(v.mean()),
        "elev_min": float(v.min()),
        "elev_p10": float(v.quantile(0.10)),
        "elev_p90": float(v.quantile(0.90)),
        "elev_max": float(v.max()),
        "elev_range": float(v.max() - v.min()),
    }


def nearest_value(point_geom, elev_gdf_utm: gpd.GeoDataFrame, max_nn_m: float) -> Tuple[float | None, float | None]:
    # returns (elev, dist_m)
    # use sjoin_nearest with a max distance cap
    try:
        joined = gpd.sjoin_nearest(
            gpd.GeoDataFrame(geometry=[point_geom], crs=elev_gdf_utm.crs),
            elev_gdf_utm[["elev","geometry"]],
            how="left",
            distance_col="dist_m",
            max_distance=max_nn_m
        )
        if joined.empty or pd.isna(joined.iloc[0].get("elev")):
            return None, None
        return float(joined.iloc[0]["elev"]), float(joined.iloc[0]["dist_m"])
    except Exception:
        return None, None


def join_elevation_to_segments(
    segments_path: Path,
    elev_csv_path: Path,
    out_csv_path: Path,
    buf_m: float = 15.0,
    max_nn_m: float = 60.0,
) -> Path:
    # 1) Load inputs
    seg = gpd.read_file(segments_path)
    elev = build_elev_gdf(elev_csv_path)

    # 2) Project to metric
    seg_utm = seg.to_crs(UTM_MNL)
    elev_utm = elev.to_crs(UTM_MNL)

    # 3) Buffer-join points inside buffer
    seg_buf = seg_utm.copy()
    seg_buf["geometry"] = seg_buf.geometry.buffer(buf_m)

    # sjoin points to buffers
    joined = gpd.sjoin(elev_utm[["elev","geometry"]], seg_buf[["geometry","segment_id"]], predicate="within", how="left")
    # group points by segment
    grp = joined.dropna(subset=["segment_id"]).groupby("segment_id")["elev"]

    # 4) Prepare output rows
    out_rows = []

    # optional fields present in the segments schema
    opt_cols = [c for c in ["corridor_id","street_label","length_m","bridge","tunnel"] if c in seg.columns]

    # index for quick segment lookup
    seg_utm = seg_utm.set_index("segment_id")

    for seg_id, row in seg.iterrows():
        segid = row.get("segment_id")
        if pd.isna(segid):
            continue
        # base info
        base = {"segment_id": segid}
        for c in opt_cols:
            base[c] = row.get(c)

        # collect buffer stats if any
        if segid in grp.groups:
            vals = grp.get_group(segid)
            stats = summarize(vals)
            n_used = int(vals.notna().sum())
            method = "buffer"
        else:
            stats = {k: None for k in ["elev_mean","elev_min","elev_p10","elev_p90","elev_max","elev_range"]}
            n_used = 0
            method = "fallback"

        # grade via nearest to endpoints
        geom_utm = seg_utm.loc[segid].geometry
        start_pt = geom_utm.interpolate(0.0, normalized=True)
        end_pt = geom_utm.interpolate(1.0, normalized=True)
        elev_start, dist_s = nearest_value(start_pt, elev_utm, max_nn_m)
        elev_end, dist_e = nearest_value(end_pt, elev_utm, max_nn_m)

        # grade
        length_m = row.get("length_m")
        try:
            length_m = float(length_m)
        except Exception:
            length_m = float(geom_utm.length)
        if elev_start is not None and elev_end is not None and length_m and length_m > 0:
            grade_pct = (elev_end - elev_start) / length_m * 100.0
        else:
            grade_pct = None

        out_rows.append({
            **base,
            **stats,
            "elev_start": elev_start,
            "elev_end": elev_end,
            "grade_pct": grade_pct,
            "n_elev_pts_used": n_used,
            "attach_method": method,
        })

    out_df = pd.DataFrame(out_rows)
    out_csv_path.parent.mkdir(parents=True, exist_ok=True)
    out_df.to_csv(out_csv_path, index=False)
    return out_csv_path

# -----------------------------
# CLI
# -----------------------------
if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--segments", type=Path, required=True)
    p.add_argument("--elev_csv", type=Path, required=True)
    p.add_argument("--out_csv", type=Path, required=True)
    p.add_argument("--buf_m", type=float, default=15.0)
    p.add_argument("--max_nn_m", type=float, default=60.0)
    args = p.parse_args()

    path = join_elevation_to_segments(
        segments_path=args.segments,
        elev_csv_path=args.elev_csv,
        out_csv_path=args.out_csv,
        buf_m=args.buf_m,
        max_nn_m=args.max_nn_m,
    )
    print(f"Wrote {path}")
