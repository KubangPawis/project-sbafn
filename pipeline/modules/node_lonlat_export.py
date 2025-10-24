"""
Helper to export per-segment lon/lat for SBAFN.

For each segment (LineString), this writes:
- segment_id
- corridor_id (if present)
- street_label
- start_lon, start_lat  (geometry start)
- end_lon, end_lat      (geometry end)
- centroid_lon, centroid_lat  (geometry centroid)
- length_m

Usage in your pipeline (after you build `segments`):

    from segment_lonlat_export import export_segment_lonlat
    export_segment_lonlat(
        segments_gdf=segments, 
        out_csv=OUTPUT_DIR / f"{TARGET_ABBR}_segments_lonlat.csv",
        also_parquet=OUTPUT_DIR / f"{TARGET_ABBR}_segments_lonlat.parquet"
    )

Notes
- Assumes `segments` is in EPSG:4326 for lon/lat output. If not, we reproject.
- If a geometry is MultiLineString (rare for segments), we use the longest LineString part.
- Centroid of a LineString is safe enough for mid-location; for along-the-line measures later we’ll store an `along_frac` value per detection.
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import geopandas as gpd
from shapely.geometry import LineString, MultiLineString


def _ensure_linestring(geom):
    if isinstance(geom, LineString):
        return geom
    if isinstance(geom, MultiLineString):
        # pick the longest part as representative
        parts = list(geom.geoms)
        if not parts:
            return None
        return max(parts, key=lambda g: g.length)
    return None


def export_segment_lonlat(
    segments_gdf: gpd.GeoDataFrame,
    out_csv: Optional[Path] = None,
    also_parquet: Optional[Path] = None,
) -> gpd.GeoDataFrame:
    """Return a DataFrame of segment endpoints + centroid lon/lat and optionally save it."""
    if segments_gdf.crs is None or segments_gdf.crs.to_epsg() != 4326:
        seg_wgs = segments_gdf.to_crs(4326)
    else:
        seg_wgs = segments_gdf.copy()

    rows = []
    cols_keep = [c for c in ["segment_id", "corridor_id", "street_label", "length_m"] if c in seg_wgs.columns]

    for _, r in seg_wgs.iterrows():
        geom = _ensure_linestring(r.geometry)
        if geom is None or geom.is_empty:
            continue
        # endpoints
        try:
            start = geom.coords[0]
            end = geom.coords[-1]
        except Exception:
            # fallback via interpolation
            start = geom.interpolate(0.0, normalized=True).coords[0]
            end = geom.interpolate(1.0, normalized=True).coords[-1]
        # centroid
        cen = geom.centroid
        row = {
            **{k: r.get(k) for k in cols_keep},
            "start_lon": float(start[0]),
            "start_lat": float(start[1]),
            "end_lon": float(end[0]),
            "end_lat": float(end[1]),
            "centroid_lon": float(cen.x),
            "centroid_lat": float(cen.y),
        }
        rows.append(row)

    out = gpd.pd.DataFrame(rows)

    if out_csv is not None:
        out.to_csv(out_csv, index=False)

    if also_parquet is not None:
        try:
            out.to_parquet(also_parquet, index=False)
        except Exception:
            pass

    return out

if __name__ == "__main__":
    print("Import export_segment_lonlat into your pipeline and call it with the segments GeoDataFrame.")