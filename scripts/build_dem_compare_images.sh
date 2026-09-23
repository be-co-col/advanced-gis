#!/usr/bin/env bash
# Builds the raw-vs-conditioned DEM comparison pair for the before/after
# slider on the hydrology page (Laacher See — a real closed volcanic basin,
# so it's the clearest illustration of what depression-filling changes).
#
# Both crops share one colour ramp (rescaled to their combined elevation
# range, not the site-wide 20-820m one, which is far too wide to show any
# contrast over this ~30m-tall bump) so a given elevation renders as the
# same colour in both images — otherwise the comparison wouldn't be
# apples-to-apples. Hillshade is then multiplied over each crop's colour
# render: the raw DEM keeps its natural relief texture, while the filled
# basin in the conditioned DEM goes flat/textureless, which is the whole
# point of the illustration.
#
# Usage: scripts/build_dem_compare_images.sh <raw.tif> <conditioned.tif>
set -euo pipefail

RAW="${1:?usage: build_dem_compare_images.sh <raw.tif> <conditioned.tif>}"
COND="${2:?usage: build_dem_compare_images.sh <raw.tif> <conditioned.tif>}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/docs/assets/img/dem-compare"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Laacher See centre, EPSG:25832 (adjust HALF to widen/narrow the AOI).
CX=377077
CY=5585648
HALF="${HALF:-2000}"
XMIN=$((CX - HALF)); XMAX=$((CX + HALF))
YMIN=$((CY - HALF)); YMAX=$((CY + HALF))
SIZE="${SIZE:-1000}" # output px, square

mkdir -p "$OUT_DIR"

crop() {
  local name="$1" src="$2"
  echo "==> [$name] cropping + reprojecting"
  gdalwarp -te "$XMIN" "$YMIN" "$XMAX" "$YMAX" -te_srs EPSG:25832 \
    -t_srs EPSG:3857 -ts "$SIZE" "$SIZE" -r cubic \
    -co COMPRESS=DEFLATE \
    "$src" "$WORK/$name-crop.tif"
}
crop raw "$RAW"
crop conditioned "$COND"

minmax() {
  gdalinfo -mm "$1" | grep "Computed Min/Max" | sed -E 's/.*=([-0-9.]+),([-0-9.]+)/\1 \2/'
}
read -r MIN1 MAX1 < <(minmax "$WORK/raw-crop.tif")
read -r MIN2 MAX2 < <(minmax "$WORK/conditioned-crop.tif")
MIN=$(awk "BEGIN{print ($MIN1<$MIN2)?$MIN1:$MIN2}")
MAX=$(awk "BEGIN{print ($MAX1>$MAX2)?$MAX1:$MAX2}")
MID=$(awk "BEGIN{printf \"%.2f\", ($MIN+$MAX)/2}")
echo "==> shared elevation range: $MIN - $MAX"

# Same green -> tan -> white progression as scripts/dem_colors.txt, just
# rescaled to this crop's own (shared) range instead of the site-wide one.
cat > "$WORK/local_colors.txt" <<EOF
$MIN  79 157  93
$MID 224 207 122
$MAX 255 255 255
nv     0   0   0   0
EOF

render() {
  local name="$1"
  gdaldem color-relief "$WORK/$name-crop.tif" "$WORK/local_colors.txt" "$WORK/$name-color.tif" -alpha
  gdaldem hillshade "$WORK/$name-crop.tif" "$WORK/$name-hillshade.tif" -z "${HILLSHADE_Z:-4}" -az 315 -alt 45
  gdal_translate -q -of PNG "$WORK/$name-color.tif" "$WORK/$name-color.png"
  gdal_translate -q -of PNG "$WORK/$name-hillshade.tif" "$WORK/$name-hillshade.png"
  magick "$WORK/$name-color.png" "$WORK/$name-hillshade.png" -compose multiply -composite \
    -quality 88 "$OUT_DIR/laacher-see-$name.jpg"
  echo "==> wrote $OUT_DIR/laacher-see-$name.jpg"
}
render raw
render conditioned

echo "done -> $OUT_DIR"
