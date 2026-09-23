#!/bin/bash
# ------------------------------------------------------------------------------
# Script: mosaic-xyz-to-tif.sh
# Purpose: Mosaic a directory of ASCII XYZ point-grid tiles into a single
#          GeoTIFF using GDAL's XYZ driver and gdalbuildvrt.
#
# Requirements:
#   - GDAL tools installed (`sudo apt install gdal-bin`)
#
# Usage:
#   bash mosaic-xyz-to-tif.sh <input_dir> <output_raster> <epsg_code>
#
# Input:
#   - input_dir: directory containing *.xyz tiles, each a regularly spaced
#     elevation point grid with no embedded CRS (e.g. LVermGeo RLP's DGM
#     open data)
#   - epsg_code: EPSG code to assign to the mosaic, e.g. 25832 for
#     ETRS89 / UTM zone 32N
#
# Output:
#   - output_raster: single GeoTIFF covering all input tiles, compressed
#     and tiled
#
# Notes:
#   - GDAL's XYZ driver requires a perfectly regular point grid; irregular
#     spacing will fail to read
#   - Building a VRT first avoids loading every tile into memory at once
# ------------------------------------------------------------------------------
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $(basename "$0") <input_dir> <output_raster> <epsg_code>"
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_RASTER="$2"
EPSG_CODE="$3"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

find "$INPUT_DIR" -maxdepth 1 -iname "*.xyz" > "$WORK/filelist.txt"
COUNT=$(wc -l < "$WORK/filelist.txt")
if [[ "$COUNT" -eq 0 ]]; then
    echo "No .xyz files found in $INPUT_DIR"
    exit 1
fi
echo "Found $COUNT tiles"

echo "==> building virtual mosaic"
gdalbuildvrt \
    -a_srs "EPSG:$EPSG_CODE" \
    -input_file_list \
    "$WORK/filelist.txt" \
    "$WORK/mosaic.vrt"

echo "==> writing single GeoTIFF"
gdal_translate \
    -a_srs \
    "EPSG:$EPSG_CODE" \
    -co COMPRESS=DEFLATE \
    -co PREDICTOR=2 \
    -co TILED=YES \
    -co BIGTIFF=IF_SAFER \
    "$WORK/mosaic.vrt" \
    "$OUTPUT_RASTER"

echo "Mosaic complete: Output saved to $OUTPUT_RASTER"
