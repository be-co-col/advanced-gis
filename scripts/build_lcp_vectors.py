#!/usr/bin/env python3
"""Builds the vector assets for the LCP bonus page: the least-cost path itself,
its source/destination points, and a curated set of context layers out of the
Arda project's full vector set (used for the toggleable overview/results maps).

Usage: scripts/build_lcp_vectors.py <arda-repo-dir>

<arda-repo-dir> is the Arda project root (the directory containing
data/output/, data/vectors/, data/rasters/) — e.g.
/mnt/data/Uni/Advanced_GIS/Session10/Arda
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "assets" / "data" / "lcp"

SRC_SRS = "EPSG:32631"

# Everything in vectors.gpkg spans a ~2000 km-wide fictional continent (vs. the
# hydrology page's much smaller real-world regional extent), so a proportionally
# coarser simplify tolerance keeps these GeoJSON files a sane size for the
# browser to fetch without visibly changing the shapes at the zoom levels this
# page is viewed at.
SIMPLIFY_M = 300

# (layer name in vectors.gpkg, output filename)
CONTEXT_LAYERS = [
    ("Roads", "roads.geojson"),
    ("Rivers", "rivers.geojson"),
    ("lakes", "lakes.geojson"),
    ("forests", "forests.geojson"),
    ("Wetlands", "wetlands.geojson"),
    ("Mountains", "mountains.geojson"),
    ("Cities", "cities.geojson"),
]


def run(cmd):
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def to_geojson(src, layer, out_name, simplify=None, drop_fields=False):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / out_name
    cmd = [
        "ogr2ogr", "-f", "GeoJSON",
        "-s_srs", SRC_SRS, "-t_srs", "EPSG:4326",
        "-lco", "COORDINATE_PRECISION=6",
    ]
    if simplify:
        cmd += ["-simplify", str(simplify)]
    if drop_fields:
        # These context layers are drawn with one flat colour per layer (no
        # styleFromProperties, no popups) — the source attributes (Tolkien
        # Mapping Resource metadata like length/bearing/origin) aren't used
        # for anything, so dropping them cuts payload size for no loss.
        cmd += ["-select", ""]
    cmd += [str(out_path), str(src)]
    if layer:
        cmd += [layer]
    run(cmd)
    return out_path


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: build_lcp_vectors.py <arda-repo-dir>")
    arda_dir = Path(sys.argv[1])
    output_dir = arda_dir / "data" / "output"
    vectors_dir = arda_dir / "data" / "vectors"
    vectors_gpkg = vectors_dir / "vectors.gpkg"

    # LCP result + endpoints — small enough (a few hundred vertices, 1 point
    # each) that no simplification is needed.
    to_geojson(output_dir / "least_cost_path.gpkg", None, "path.geojson")
    to_geojson(vectors_dir / "source_layer.gpkg", None, "source.geojson")
    to_geojson(vectors_dir / "dest_layer.gpkg", None, "destination.geojson")

    # Curated context layers for the toggleable overview/results maps.
    for layer, out_name in CONTEXT_LAYERS:
        to_geojson(vectors_gpkg, layer, out_name, simplify=SIMPLIFY_M, drop_fields=True)

    print("done ->", OUT_DIR)


if __name__ == "__main__":
    main()
