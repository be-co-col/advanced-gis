#!/usr/bin/env python3
"""Builds the vector assets for the hydrology page: streams (styled by
discharge), the delineated watershed, and the pour point used to derive it.

Usage: scripts/build_hydrology_vectors.py <session07-0_results-dir>
"""
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "assets" / "data" / "hydrology"

# Sequential blue ramp (ColorBrewer "Blues"-style endpoints) and a line-weight
# range, both interpolated over log10(max_accum) — flow accumulation spans
# several orders of magnitude, so a linear scale would make everything but
# the largest rivers look identical.
COLOR_LOW = (168, 216, 255)  # light blue — small headwater streams
COLOR_HIGH = (8, 48, 107)  # dark blue — major rivers
WEIGHT_LOW = 1.0
WEIGHT_HIGH = 5.0


def run(cmd):
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def lerp(a, b, t):
    return a + (b - a) * t


def color_for(t):
    r = round(lerp(COLOR_LOW[0], COLOR_HIGH[0], t))
    g = round(lerp(COLOR_LOW[1], COLOR_HIGH[1], t))
    b = round(lerp(COLOR_LOW[2], COLOR_HIGH[2], t))
    return "#{:02x}{:02x}{:02x}".format(r, g, b)


def style_streams(path):
    data = json.loads(path.read_text())
    values = [math.log10(f["properties"]["max_accum"]) for f in data["features"]]
    lo, hi = min(values), max(values)
    for feature, log_val in zip(data["features"], values):
        t = (log_val - lo) / (hi - lo) if hi > lo else 0.0
        feature["properties"]["color"] = color_for(t)
        feature["properties"]["weight"] = round(lerp(WEIGHT_LOW, WEIGHT_HIGH, t), 2)
    path.write_text(json.dumps(data))
    print(f"styled {len(data['features'])} stream segments (log10 max_accum {lo:.2f}-{hi:.2f})")


def to_geojson(src, out_name, source_srs=None, simplify=None):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / out_name
    cmd = ["ogr2ogr", "-f", "GeoJSON", "-t_srs", "EPSG:4326", "-lco", "COORDINATE_PRECISION=6"]
    if source_srs:
        # Overrides whatever SRS (or lack thereof) is recorded in the source file.
        cmd += ["-s_srs", source_srs]
    if simplify:
        cmd += ["-simplify", str(simplify)]
    cmd += [str(out_path), str(src)]
    run(cmd)
    return out_path


def clip_to_watershed(streams_path, watershed_path):
    # For the watershed map, which only wants the catchment's own network,
    # not the full study-area extent shown on the streams map above it.
    out_path = OUT_DIR / "streams-watershed.geojson"
    run(["ogr2ogr", "-f", "GeoJSON", "-clipsrc", str(watershed_path), str(out_path), str(streams_path)])
    print(f"clipped streams to watershed -> {out_path}")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: build_hydrology_vectors.py <session07-0_results-dir>")
    src_dir = Path(sys.argv[1])

    # streams.gpkg has no SRS recorded in the file itself, despite being in
    # EPSG:25832 (confirmed by extent overlap with watershed.gpkg).
    streams_out = to_geojson(src_dir / "streams.gpkg", "streams.geojson", source_srs="EPSG:25832", simplify=5)
    style_streams(streams_out)

    watershed_out = to_geojson(src_dir / "watershed.gpkg", "watershed.geojson")
    to_geojson(src_dir / "pour_point_snapped.shp", "pour-point.geojson")

    clip_to_watershed(streams_out, watershed_out)

    print("done ->", OUT_DIR)


if __name__ == "__main__":
    main()
