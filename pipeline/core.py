from pathlib import Path

import osmnx as ox
import folium
import yaml

# -----------------------

REPO_ROOT = Path(__file__).resolve().parents[1]
PIPELINE_DIR = REPO_ROOT / "pipeline"

with open(PIPELINE_DIR / "configs" / "config.yaml", "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

# CONFIGS: FOLIUM
TARGET_PLACE_NAME = cfg["aoi"].get("name", "Manila, Philippines")
TARGET_AREA_NAME = cfg["aoi"].get("name", "Manila")
TARGET_ABBR = cfg["aoi"].get("abbr", "mnl")
STARTING_LAT = cfg["folium"].get("starting_lat", 0)
STARTING_LONG = cfg["folium"].get("starting_long", 0)
ZOOM_START = cfg["folium"].get("zoom_start", 12)

# CONFIGS: OUTPUT PATHS
OUTPUT_DIR = PIPELINE_DIR / "outputs"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

print(f"Starting Position: ({STARTING_LAT}, {STARTING_LONG}) | Zoom Start: {ZOOM_START}")

# -----------------------

def main():
    '''
        Target Place: Manila, Philippines
        Data: Street Network (Driving)
        Source: OpenStreetMap
    '''

    G = ox.graph_from_place(TARGET_PLACE_NAME, network_type="drive", simplify=True)
    nodes, edges = ox.graph_to_gdfs(G)

    nodes_wgs = nodes.to_crs(4326).reset_index() # CRS = WGS84
    edges_wgs = edges.to_crs(4326)

    # FOLIUM MAP
    m = folium.Map(location=(STARTING_LAT, STARTING_LONG), zoom_start=ZOOM_START, tiles="CartoDB positron")

    folium.GeoJson(
        edges_wgs.to_json(),
        name=f"{TARGET_AREA_NAME} Streets",
        tooltip=folium.features.GeoJsonTooltip(fields=["name", "highway", "length"])
    ).add_to(m)

    # Render only nodes with 3 or more connecting streets (intersections)
    intersections = nodes_wgs[nodes_wgs["street_count"] >= 3]
    for y,x in zip(intersections.geometry.y, intersections.geometry.x):
        folium.CircleMarker([y,x], radius=2, color="red", fill=True, fill_opacity=0.8).add_to(m)

    folium.LayerControl().add_to(m)

    # DATA EXPORT
    m_outdir = OUTPUT_DIR / "maps"
    m_outdir.mkdir(parents=True, exist_ok=True)
    m.save(m_outdir / f"{TARGET_ABBR}_street_network.html")

    _save_nodes_edges_to_csv(nodes=nodes_wgs, edges=edges_wgs, outdir=OUTPUT_DIR, target_name=TARGET_ABBR)

#  ------------- UTILITY FUNCTIONS -------------

def _save_nodes_edges_to_csv(nodes, edges, outdir: Path, target_name: str):
    target = outdir / f"{target_name}_nodes_edges"
    target.mkdir(parents=True, exist_ok=True)    

    # NODES → CSV
    nodes_out = nodes.reset_index()
    nodes_out["geometry_wkt"] = nodes_out.geometry.to_wkt()
    nodes_out = nodes_out.drop(columns=["geometry"])
    nodes_out.to_csv(target / f"{target_name}_nodes.csv", index=False)

    #EDGES → CSV
    edges_out = edges.reset_index()
    for col in ("highway", "name", "osmid"):
        if col in edges_out.columns:
            edges_out[col] = edges_out[col].apply(lambda x: ", ".join(map(str, x)) if isinstance(x, list) else x)

    edges_out["geometry_wkt"] = edges_out.geometry.to_wkt()
    edges_out = edges_out.drop(columns=["geometry"])
    edges_out.to_csv(target / f"{target_name}_edges.csv", index=False)

# -----------------------

if __name__ == "__main__":
    main()