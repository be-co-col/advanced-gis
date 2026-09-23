#!/usr/bin/env bash
# Generalized version of build_dem_tiles.sh for the other hydrology rasters
# (conditioned DEM, flow direction, flow accumulation). Same pipeline —
# reproject to EPSG:3857 at full native resolution -> bake in a colour ramp
# with gdaldem color-relief -> cut an XYZ tile pyramid — but parameterized
# so each raster can pick its own resampling method (categorical data like
# flow direction must use nearest-neighbor, never bilinear) and optionally
# a log10 transform first (flow accumulation's range spans several orders
# of magnitude; a linear ramp on raw values would be unreadable).
#
# Usage:
#   scripts/build_raster_tiles.sh <source.tif> <output-dir-name> <colors.txt>
#
# Optional env vars:
#   RESAMPLING=near|bilinear   (default: bilinear)
#   LOG_TRANSFORM=1            apply log10(x+1) before colouring
#   EXACT_COLOR=1              pass -exact_color_entry to gdaldem (categorical rasters)
#   MINZOOM=6 MAXZOOM=12       (defaults: 6-12, matching the DEM's native resolution)
set -euo pipefail

SRC="${1:?usage: build_raster_tiles.sh <source.tif> <output-dir-name> <colors.txt>}"
OUT_NAME="${2:?usage: build_raster_tiles.sh <source.tif> <output-dir-name> <colors.txt>}"
COLORS="${3:?usage: build_raster_tiles.sh <source.tif> <output-dir-name> <colors.txt>}"
RESAMPLING="${RESAMPLING:-bilinear}"
MINZOOM="${MINZOOM:-6}"
MAXZOOM="${MAXZOOM:-12}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/docs/assets/data/$OUT_NAME"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> reprojecting to EPSG:3857 (full native resolution, $RESAMPLING)"
gdalwarp -t_srs EPSG:3857 -r "$RESAMPLING" \
  -co COMPRESS=DEFLATE -co PREDICTOR=2 -co TILED=YES -co BIGTIFF=IF_SAFER \
  -co NUM_THREADS=ALL_CPUS \
  "$SRC" "$WORK/reprojected.tif"

COLOR_INPUT="$WORK/reprojected.tif"
if [ "${LOG_TRANSFORM:-0}" = "1" ]; then
  echo "==> applying log10(x+1) transform"
  gdal_calc.py -A "$WORK/reprojected.tif" --outfile="$WORK/log.tif" \
    --calc="where(A==-32768, -9999, log10(A+1))" \
    --NoDataValue=-9999 --type=Float32 --co COMPRESS=DEFLATE
  COLOR_INPUT="$WORK/log.tif"
fi

echo "==> applying colour ramp ($COLORS)"
EXACT_FLAG=()
if [ "${EXACT_COLOR:-0}" = "1" ]; then
  EXACT_FLAG=(-exact_color_entry)
fi
gdaldem color-relief "$COLOR_INPUT" "$COLORS" "$WORK/rgba.tif" \
  -alpha "${EXACT_FLAG[@]}" -co COMPRESS=DEFLATE -co TILED=YES -co BIGTIFF=IF_SAFER \
  -co NUM_THREADS=ALL_CPUS

echo "==> cutting tiles ($MINZOOM-$MAXZOOM) into $OUT_DIR"
rm -rf "$OUT_DIR"
RESAMPLE_FOR_TILES="$RESAMPLING"
if [ "$RESAMPLING" = "near" ]; then RESAMPLE_FOR_TILES="near"; else RESAMPLE_FOR_TILES="bilinear"; fi
gdal2tiles.py --xyz -w none -x -r "$RESAMPLE_FOR_TILES" -z "$MINZOOM-$MAXZOOM" \
  --processes="$(nproc)" "$WORK/rgba.tif" "$OUT_DIR"

du -sh "$OUT_DIR"
echo "done."
