#!/bin/bash
# ------------------------------------------------------------------------------
# Script: clip_raster_via_vector.sh
# Purpose: Clip a raster layer to a boundary vector using GDAL's gdalwarp.
#
# Requirements:
#   - GDAL tools installed (`sudo apt install gdal-bin`)
#
# Usage:
#   bash clip-raster-via-vector.sh <vector> <input_raster> <output_raster> [nodata_value]
#
# Input:
#   - vector: shapefile or GeoJSON used as cutline
#   - input_raster: raster to clip (GeoTIFF or VRT)
#   - nodata_value: optional; overrides the output NoData value. Defaults to
#     the input raster's own NoData value if omitted.
#
# Output:
#   - output_raster: GeoTIFF clipped to the vector boundary, compressed and
#     tiled, matching the input raster's data type. An alpha band is added
#     so areas outside the cutline render transparent in QGIS/ArcGIS, while
#     the NoData value is still set for analysis in other tools.
#
# Notes:
#   - CRS must match between raster and vector
#   - Use ogr2ogr to reproject vector if necessary
# ------------------------------------------------------------------------------
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $(basename "$0") <vector> <input_raster> <output_raster> [nodata_value]"
    exit 1
fi

SHAPEFILE="$1"
INPUT_RASTER="$2"
OUTPUT_RASTER="$3"
USER_NODATA="${4:-}"

# Read data type and nodata value from the input raster (first band) so the
# output stays consistent with the source instead of assuming a fixed type.
RASTER_INFO=$(gdalinfo "$INPUT_RASTER")
DATA_TYPE=$(grep -m1 -oP '(?<=Type=)[A-Za-z0-9]+' <<< "$RASTER_INFO" || true)
SRC_NODATA=$(grep -m1 -oP '(?<=NoData Value=)\S+' <<< "$RASTER_INFO" || true)

if [[ -n "$USER_NODATA" ]]; then
    DST_NODATA="$USER_NODATA"
elif [[ -n "$SRC_NODATA" ]]; then
    DST_NODATA="$SRC_NODATA"
else
    echo "Input raster has no NoData value defined, using -9999 for the output."
    DST_NODATA=-9999
fi

WARP_ARGS=(-cutline
           "$SHAPEFILE"
           -crop_to_cutline
           -dstalpha
           -dstnodata
           "$DST_NODATA"
           -of GTiff
           -co COMPRESS=DEFLATE
           -co TILED=YES
           -co INTERLEAVE=BAND
           -overwrite)

if [[ -n "$SRC_NODATA" ]]; then
    WARP_ARGS+=(-srcnodata "$SRC_NODATA")
fi

if [[ -n "$DATA_TYPE" ]]; then
    WARP_ARGS+=(-ot "$DATA_TYPE")
else
    echo "Could not determine input data type, letting gdalwarp decide."
fi

# Perform the clipping
gdalwarp "${WARP_ARGS[@]}" "$INPUT_RASTER" "$OUTPUT_RASTER"

echo "Clipping complete: Output saved to $OUTPUT_RASTER"
