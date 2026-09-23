#!/usr/bin/env bash
# Builds a baseline-vs-refined suitability comparison pair for a before/after
# slider, the same way build_dem_compare_images.sh does for Laacher See.
#
# Suitable area for this study region is scattered across thousands of small
# patches — a whole-region slider doesn't usefully show "what changed" the
# way it does for a single compact feature, so this is meant for one
# deliberately-chosen, visually clear AOI (set CX/CY/HALF below), not the
# full extent.
#
# IMPORTANT: unlike the webmap layers (which want transparency so the
# basemap shows through), a compare-slider's "after" image must be fully
# OPAQUE wherever it has data — compare-slider.js layers the after-image on
# top of the before-image and reveals it via clip-path, so a transparent
# "not suitable" pixel lets the before-image bleed through underneath,
# making the comparison meaningless. Both colour entries below use alpha 255.
#
# Usage: scripts/build_suitability_compare_images.sh <baseline.tif> <refined.tif>
set -euo pipefail

BASELINE="${1:?usage: build_suitability_compare_images.sh <baseline.tif> <refined.tif>}"
REFINED="${2:?usage: build_suitability_compare_images.sh <baseline.tif> <refined.tif>}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/docs/assets/img/suitability-compare"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# AOI centre, EPSG:25832 — set these to whatever hotspot you're illustrating
# (e.g. a stretch of valley where the frost buffer visibly carves a wide
# corridor out of an otherwise solid suitable band). No sensible universal
# default exists, so this errors out until you pick one.
CX="${CX:?set CX (EPSG:25832 easting) for the AOI centre}"
CY="${CY:?set CY (EPSG:25832 northing) for the AOI centre}"
HALF="${HALF:-1500}"
XMIN=$((CX - HALF)); XMAX=$((CX + HALF))
YMIN=$((CY - HALF)); YMAX=$((CY + HALF))
SIZE="${SIZE:-1000}" # output px, square

mkdir -p "$OUT_DIR"

# 0 = not suitable -> opaque neutral background
# 1 = suitable      -> opaque green
cat > "$WORK/suit_colors.txt" <<EOF
0   60  56  54  255
1  137 180 130  255
nv   0   0   0  255
EOF

render() {
  local name="$1" src="$2"
  echo "==> [$name] cropping + reprojecting"
  gdalwarp -te "$XMIN" "$YMIN" "$XMAX" "$YMAX" -te_srs EPSG:25832 \
    -t_srs EPSG:3857 -ts "$SIZE" "$SIZE" -r near \
    -co COMPRESS=DEFLATE \
    "$src" "$WORK/$name-crop.tif"
  gdaldem color-relief -alpha -exact_color_entry "$WORK/$name-crop.tif" "$WORK/suit_colors.txt" "$WORK/$name-color.tif"
  gdal_translate -q -of PNG "$WORK/$name-color.tif" "$OUT_DIR/$name.png"
  echo "==> wrote $OUT_DIR/$name.png"
}
render baseline "$BASELINE"
render refined "$REFINED"

echo "done -> $OUT_DIR"
