#!/usr/bin/env bash
# Builds the DEM assets served on the "DEM" page.
#
# Pipeline: reproject the elevation band at full native resolution (kept as
# docs/assets/data/dem-elevation.tif, a plain tiled GeoTIFF used only for
# the click-to-read-elevation popup via windowed HTTP-range reads) -> bake
# a colour ramp in with `gdaldem color-relief` (edit scripts/dem_colors.txt
# to change the ramp) -> cut an XYZ tile pyramid with gdal2tiles for the
# visible basemap-style layer. So the browser draws a normal Leaflet tile
# layer (no client-side GeoTIFF parsing for display) but can still look up
# an exact elevation value on click.
#
# Usage: scripts/build_dem_tiles.sh /path/to/source-dem.tif
set -euo pipefail

SRC="${1:?usage: build_dem_tiles.sh <source-dem.tif>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_DIR="$ROOT/docs/assets/data"
OUT_DIR="$DATA_DIR/dem-tiles"
ELEV_OUT="$DATA_DIR/dem-elevation.tif"
COLORS="$ROOT/scripts/dem_colors.txt"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MINZOOM=6
MAXZOOM=12 # ~25 m/px at 50°N — matches the source DEM's native resolution

echo "==> extracting elevation band"
gdal_translate -b 1 -co COMPRESS=DEFLATE -co PREDICTOR=3 -co TILED=YES \
  "$SRC" "$WORK/elev.tif"

echo "==> reprojecting to EPSG:3857 (full native resolution, rounded to whole metres)"
rm -f "$ELEV_OUT"
gdalwarp -t_srs EPSG:3857 -r bilinear -ot Int16 -dstnodata -32768 \
  -co COMPRESS=DEFLATE -co PREDICTOR=2 -co TILED=YES -co BIGTIFF=IF_SAFER \
  -co NUM_THREADS=ALL_CPUS \
  "$WORK/elev.tif" "$ELEV_OUT"

echo "==> applying colour ramp ($COLORS)"
gdaldem color-relief "$ELEV_OUT" "$COLORS" "$WORK/rgba.tif" \
  -alpha -co COMPRESS=DEFLATE -co TILED=YES -co BIGTIFF=IF_SAFER \
  -co NUM_THREADS=ALL_CPUS

echo "==> cutting tiles ($MINZOOM-$MAXZOOM) into $OUT_DIR"
rm -rf "$OUT_DIR"
gdal2tiles.py --xyz -w none -x -r bilinear -z "$MINZOOM-$MAXZOOM" \
  --processes="$(nproc)" "$WORK/rgba.tif" "$OUT_DIR"

du -sh "$OUT_DIR" "$ELEV_OUT"
echo "done."
