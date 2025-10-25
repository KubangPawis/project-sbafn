"""
Street segmentation + corridor construction for SBAFN

Inputs
- edges_gdf: GeoDataFrame from osmnx.graph_to_gdfs(G) (edges), WGS84 (epsg:4326) or any CRS

Outputs
- segments_gdf: intersection-to-intersection edges (optionally split to target length)
  columns (suggested):
    segment_id, parent_u, parent_v, parent_key, corridor_id (filled after make_corridors),
    street_label, highway,  lanes, length_m, geometry (LineString)

- corridors_gdf: connected pieces per normalized name
  columns: corridor_id, name, n_segments, total_length_m, highway_mode, geometry

Notes
- Project to a metric CRS for length-based splitting; default uses UTM zone from centroid (safe for city scale)
- Name normalization prefers `name`; falls back to `ref` then `highway`
- Handles `name`/`highway` lists from OSMnx by taking first non-null item
- Dual carriageways remain separate corridors; optional merge hook included
"""
from __future__ import annotations
from typing import Optional

import geopandas as gpd
import pandas as pd
from shapely.geometry import LineString
import numpy as np
import networkx as nx

# -----------------------------
# Utility helpers
# -----------------------------

def _first_non_null(value):
    if isinstance(value, (list, tuple)):
        for v in value:
            if pd.notna(v) and str(v).strip():
                return str(v)
        return None
    return value if (pd.notna(value) and str(value).strip()) else None


def _normalize_street_label(row: pd.Series) -> str:
    name = _first_non_null(row.get("name"))
    ref = _first_non_null(row.get("ref"))
    hw  = _first_non_null(row.get("highway"))
    label = name or ref or hw or "unnamed"
    return str(label)


def _pick_metric_crs(gdf: gpd.GeoDataFrame) -> str:
    """Choose a UTM zone based on the geometry centroid (good enough for city scale)."""
    # EPSG:4326 expected; get centroid lon/lat
    centroid = gdf.to_crs(4326).unary_union.centroid
    lon, lat = centroid.x, centroid.y
    zone = int((lon + 180) // 6) + 1
    south = lat < 0
    epsg = 32700 + zone if south else 32600 + zone  # 326XX = UTM north, 327XX = UTM south
    return f"EPSG:{epsg}"


def _explode_linestring(ls: LineString, max_len: float) -> list[LineString]:
    """Split a LineString into ~equal subsegments not exceeding max_len (meters)."""
    if max_len is None or ls.length <= max_len:
        return [ls]
    # number of cuts = ceil(total/max_len)
    n = int(np.ceil(ls.length / max_len))
    if n <= 1:
        return [ls]
    # sample points along the line at equal fractions
    fracs = np.linspace(0, 1, n + 1)
    pts = [ls.interpolate(d, normalized=True) for d in fracs]
    parts = []
    for i in range(len(pts) - 1):
        seg = LineString([pts[i], pts[i+1]])
        # preserve curvature by densifying against original? For now keep straight chord; 
        # if geometry has many vertices, consider segmentize before splitting.
        parts.append(seg)
    return parts

# -----------------------------
# Public API
# -----------------------------

def make_segments(
    edges_gdf: gpd.GeoDataFrame,
    split_len_m: Optional[int] = 30,
    metric_crs: Optional[str] = None,
) -> gpd.GeoDataFrame:
    """
    Build model-ready "segments" from OSMnx edges.

    - Normalizes street names to `street_label`
    - Keeps key attributes
    - Optionally splits long edges into ~split_len_m chunks (in meters)

    Returns GeoDataFrame in EPSG:4326 with columns:
      segment_id, parent_u, parent_v, parent_key, street_label,
      highway, lanes, length_m, geometry
    """
    if edges_gdf.empty:
        return edges_gdf.copy()

    edges = edges_gdf.reset_index().copy()

    # normalize columns
    for col in ("name", "ref", "highway"):
        if col not in edges.columns:
            edges[col] = None

    edges["street_label"] = edges.apply(_normalize_street_label, axis=1)

    keep_cols = [
        "u", "v", "key", "street_label", "highway", "lanes", "geometry"
    ]
    for c in keep_cols:
        if c not in edges.columns:
            edges[c] = None
    edges = edges[keep_cols].copy()

    # flatten list-like columns to scalars (Parquet-safe)
    for col in ("highway", "lanes"):
        edges[col] = edges[col].apply(lambda v: _first_non_null(v) if isinstance(v, (list, tuple)) else v)

    # project to metric for splitting/lengths
    metric = metric_crs or _pick_metric_crs(edges)
    wm = edges.to_crs(metric)

    rows = []
    for idx, r in wm.iterrows():
        geom: LineString = r.geometry
        parts = _explode_linestring(geom, split_len_m) if split_len_m else [geom]
        for j, p in enumerate(parts):
            length_m = float(p.length)
            seg = {
                "parent_u": r["u"],
                "parent_v": r["v"],
                "parent_key": r["key"],
                "street_label": r["street_label"],
                "highway": r.get("highway"),
                "lanes": r.get("lanes"),
                "length_m": length_m,
                "_part": j,
                "geometry": p,
            }
            rows.append(seg)

    segs = gpd.GeoDataFrame(rows, crs=metric)

    # build stable segment_id from parent edge and part index
    segs["segment_id"] = (
        segs["parent_u"].astype(str) + "_" + segs["parent_v"].astype(str) + "_" +
        segs["parent_key"].astype(str) + "_p" + segs["_part"].astype(str)
    )
    segs = segs.drop(columns=["_part"])  # internal

    # back to WGS84 for storage/web
    segs = segs.to_crs(4326)
    segs = segs[
        [
            "segment_id", "parent_u", "parent_v", "parent_key",
            "street_label", "highway", "lanes", "length_m", "geometry",
        ]
    ]
    return segs


def make_corridors(
    segments_gdf: gpd.GeoDataFrame,
    merge_dual: bool = False,
    merge_buffer_m: float = 8.0,
    metric_crs: Optional[str] = None,
) -> tuple[gpd.GeoDataFrame, gpd.GeoDataFrame]:
    """
    Build human-friendly "corridors" by connected components per street_label.

    Returns (corridors_gdf, segments_with_corridor_id)
    - corridors columns: corridor_id, name, n_segments, total_length_m, highway_mode, geometry
    - segments gains: corridor_id

    merge_dual: if True, merges dual carriageways with identical labels that sit within merge_buffer_m of each other
    """
    segs = segments_gdf.copy()
    if segs.empty:
        return gpd.GeoDataFrame(columns=["corridor_id", "name", "n_segments", "total_length_m", "highway_mode", "geometry"], crs=segs.crs), segs

    # ensure label
    if "street_label" not in segs.columns:
        raise ValueError("segments_gdf must contain 'street_label'")

    # compute a dominant highway type per corridor later
    if "highway" not in segs.columns:
        segs["highway"] = None

    # work in metric for dissolves/buffers
    metric = metric_crs or _pick_metric_crs(segs)
    wm = segs.to_crs(metric)

    # map from segment_id to corridor_id
    corr_ids = []

    grouped = wm.groupby("street_label", dropna=False)
    for name, df in grouped:
        # Build undirected graph on parent nodes (works even after splitting because we still carry parent_u/v)
        Gname = nx.Graph()
        Gname.add_edges_from(df[["parent_u", "parent_v"]].dropna().itertuples(index=False, name=None))
        if Gname.number_of_edges() == 0 and len(df) > 0:
            # isolated single-segment with missing parent ids; treat as one component
            comps = [set(range(len(df)))]
            comp_index_by_row = {i:0 for i in range(len(df))}
        else:
            comps = list(nx.connected_components(Gname))
            # Assign rows to components by matching their parent_u nodes
            node_to_comp = {}
            for i, comp in enumerate(comps):
                for n in comp:
                    node_to_comp[n] = i
            comp_index_by_row = df["parent_u"].map(node_to_comp).fillna(0).astype(int).to_dict()

        # Apply IDs
        slug = str(name or "unnamed").lower().strip().replace(" ", "_")
        # Guarantee uniqueness by adding component index
        local_ids = []
        for ridx, r in df.reset_index().iterrows():
            comp_idx = comp_index_by_row.get(r["parent_u"], 0)
            local_ids.append(f"{slug}_{comp_idx}")
        corr_ids.extend(local_ids)

    wm["corridor_id"] = corr_ids

    # Optional: merge dual carriageways by buffering and dissolving corridors with same name that touch within buffer
    if merge_dual:
        # dissolve by (name, corridor_id) first to get clean pieces
        base = wm.dissolve(by=["street_label", "corridor_id"], aggfunc={})
        base = base.reset_index()
        # group by name, buffer, dissolve overlaps
        merged_rows = []
        for name, df in base.groupby("street_label", dropna=False):
            buf = df.copy()
            buf["geometry"] = buf.geometry.buffer(merge_buffer_m)
            # dissolve overlapping buffers, then carry original geometry union
            buf_diss = buf.dissolve()
            # map dissolved parts back is non-trivial; keep simple: one merged geometry per name
            geom_union = df.geometry.unary_union
            merged_rows.append({
                "street_label": name,
                "geometry": geom_union
            })
        merged = gpd.GeoDataFrame(merged_rows, crs=metric)
        merged["corridor_id"] = merged["street_label"].str.lower().str.replace(" ", "_", regex=False)
        corridors = merged
        # assign segments to merged corridors by name match
        wm = wm.merge(corridors[["street_label", "corridor_id"]], on="street_label", suffixes=("", "_merged"))
        wm["corridor_id"] = wm["corridor_id_merged"]
        wm = wm.drop(columns=["corridor_id_merged"])

    # Build corridors table (sum length, pick mode)
    # Recompute length in metric CRS reliably
    wm["_len"] = wm.geometry.length
    agg = (
        wm.groupby("corridor_id")
          .agg(
              name=("street_label", "first"),
              n_segments=("segment_id", "count"),
              total_length_m=("_len", "sum"),
              highway_mode=("highway", lambda s: s.dropna().iloc[0] if len(s.dropna()) else None),
              geometry=("geometry", lambda g: g.unary_union)
          )
          .reset_index()
    )
    corridors = gpd.GeoDataFrame(agg, geometry="geometry", crs=metric).to_crs(4326)

    # Attach corridor_id back onto segments (WGS84)
    segs_out = wm[["segment_id", "corridor_id"]].merge(segs, on="segment_id", how="right")
    segs_out = gpd.GeoDataFrame(segs_out, geometry="geometry", crs=segs.crs)

    # Final tidy columns
    corridors = corridors[["corridor_id", "name", "n_segments", "total_length_m", "highway_mode", "geometry"]]

    return corridors, segs_out

# -----------------------------
if __name__ == "__main__":
    print("This module provides make_segments() and make_corridors(). Import and call from your pipeline.")
