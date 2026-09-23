#!/usr/bin/env python3
"""Builds the vector assets for the suitability-model page: the DEM-only
baseline, and for each refinement (hydro, solar, combined) a pair of
"resulting suitable area" / "area cut by this refinement" layers —
reprojected to EPSG:4326 and filtered to only the class that needs a fill
on the map.

Usage: scripts/build_suitability_vectors.py <session05-results-dir> <solar-dir> <suitability-dir>
  e.g. scripts/build_suitability_vectors.py Data/Session05/results Data/Solar/grass/RLP Data/Suitability
"""
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "assets" / "data" / "suitability"

# Raster-derived polygons at ~25 m resolution have stairstep edges from the
# grid; this knocks vertex count down to something reasonable for a static
# page to load. Tuned empirically — 15 produced 10-20MB files (far too heavy
# next to hydrology.md's ~300KB watershed.geojson), 50 keeps shapes
# recognisable at web-map zoom levels while cutting size drastically.
SIMPLIFY = 50


def run(cmd):
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def to_geojson(src, out_name, where=None, simplify=SIMPLIFY):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / out_name
    cmd = ["ogr2ogr", "-f", "GeoJSON", "-t_srs", "EPSG:4326", "-lco", "COORDINATE_PRECISION=6"]
    if where:
        cmd += ["-where", where]
    if simplify:
        cmd += ["-simplify", str(simplify)]
    cmd += [str(out_path), str(src)]
    run(cmd)
    print(f"wrote {out_path}")
    return out_path


def main():
    if len(sys.argv) != 4:
        sys.exit("usage: build_suitability_vectors.py <session05-results-dir> <solar-dir> <suitability-dir>")
    session05_dir = Path(sys.argv[1])
    solar_dir = Path(sys.argv[2])
    suitability_dir = Path(sys.argv[3])

    # DEM-only baseline
    to_geojson(session05_dir / "RLP-suitability.gpkg", "baseline.geojson", where="suitability=1")

    # Hydrology (frost) refinement: resulting suitable area + area cut by it
    to_geojson(
        suitability_dir / "suitability_hydro_combined.gpkg",
        "hydro-result.geojson",
        where="suitability_hydro_combined=1",
    )
    to_geojson(
        suitability_dir / "suitability_hydro_diff.gpkg",
        "hydro-removed.geojson",
        where="removed_by_hydro=1",
    )

    # Solar refinement: resulting suitable area + area cut by it
    to_geojson(solar_dir / "suitability_combined.gpkg", "solar-result.geojson", where="suitability_combined=1")
    to_geojson(solar_dir / "suitability_diff.gpkg", "solar-removed.geojson", where="removed_by_solar=1")

    # Combined model: resulting suitable area + area cut by either refinement
    to_geojson(suitability_dir / "suitability_full.gpkg", "full-refined.geojson", where="suitability_full=1")
    to_geojson(suitability_dir / "suitability_full_removed.gpkg", "full-removed.geojson", where="removed_full=1")

    print("done ->", OUT_DIR)


if __name__ == "__main__":
    main()
