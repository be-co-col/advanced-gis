# =============================================================================
# SIMPLE SUITABILITY ANALYSIS BASED ON ELEVATION, SLOPE AND ASPECT
# =============================================================================

# =============================================================================
# CLEAN ENVIRONMENT AND LOAD LIBRARIES
# =============================================================================

rm(list = ls())

library(terra)
library(jsonlite)

# =============================================================================
# INPUT & THRESHOLDS
# =============================================================================

dem_path <- "Data/DEM/RLP-DEM.tif" # path to DEM (if multiple bands -> 1.)

docs_repo_path <- file.path(Sys.getenv("HOME"), "Dev/advanced-gis")

# Elevation thresholds (metres)
elev_min <- 0
elev_max <- 260

# Slope thresholds
slope_unit <- "percent"   # "degrees" or "percent"
slope_min  <- 10
slope_max  <- 55

# Aspect thresholds (degrees, 0–360, clockwise from north)
# Set to NA to skip the aspect filter entirely.
# For ranges that cross 0°/360° (e.g. north-facing 315–45°) the script
# handles the wrap-around automatically.
aspect_min <- 112.5   # e.g. 135 = SE
aspect_max <- 247.5   # e.g. 225 = SW

# Output files
out_path     <- "Data/Session05/results/RLP-suitability.tif"
out_vec_path <- "Data/Session05/results/RLP-suitability.gpkg"
out_report   <- file.path(docs_repo_path, "docs/assets/data/suitability/report_baseline.json")

# =============================================================================
# LOAD DEM
# =============================================================================

dem <- rast(dem_path)

# If the file has multiple bands, use only the first
if (nlyr(dem) > 1) {
  message("Multi-band raster detected — using band 1 only.")
  dem <- dem[[1]]
}

# =============================================================================
# DERIVE TERRAIN VARIABLES
# =============================================================================

slope <- terrain(dem, v = "slope", unit = "degrees")
if (slope_unit == "percent") slope <- tan(slope * pi / 180) * 100
aspect <- terrain(dem, v = "aspect", unit = "degrees")

# =============================================================================
# BINARY SUITABILITY MASKS
# =============================================================================

suit_elev  <- (dem   >= elev_min)  & (dem   <= elev_max)
suit_slope <- (slope >= slope_min) & (slope <= slope_max)

if (!is.na(aspect_min) && !is.na(aspect_max)) {
  if (aspect_min <= aspect_max) {
    # Simple range (e.g. 135–225°)
    suit_aspect <- (aspect >= aspect_min) & (aspect <= aspect_max)
  } else {
    # Wrap-around range (e.g. 315–45°, crosses north)
    suit_aspect <- (aspect >= aspect_min) | (aspect <= aspect_max)
  }
} else {
  # No aspect filter — everything is suitable
  suit_aspect <- dem * 0 + 1
}

# =============================================================================
# COMBINE INTO FINAL SUITABILITY LAYER
# =============================================================================

# All three conditions must be TRUE (1 = suitable, 0 = not suitable)
suitability <- suit_elev & suit_slope & suit_aspect

# Cast to integer so the output is a clean 0/1 raster
suitability <- as.int(suitability)
names(suitability) <- "suitability"

# =============================================================================
# QUICK SUMMARY
# =============================================================================

total_cells    <- ncell(suitability) - global(suitability, fun = "isNA")[[1]]
suitable_cells <- global(suitability, fun = "sum", na.rm = TRUE)[[1]]
pct_suitable   <- round(suitable_cells / total_cells * 100, 1)

message(sprintf(
  "Suitable area: %s cells out of %s valid cells (%.1f%%)",
  formatC(suitable_cells, format = "f", digits = 0, big.mark = ","),
  formatC(total_cells,    format = "f", digits = 0, big.mark = ","),
  pct_suitable
))

# =============================================================================
# JSON REPORT
# =============================================================================

cell_area_ha <- (res(dem)[1] * res(dem)[2]) / 10000

criterion_summary <- function(mask) {
  cells <- global(as.int(mask), "sum", na.rm = TRUE)[[1]]
  list(
    cells       = cells,
    ha          = round(cells * cell_area_ha, 1),
    pct_of_total = round(cells / total_cells * 100, 1)
  )
}

report <- list(
  label        = "DEM-only baseline",
  script       = "suitability_analysis.R",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  cell_area_ha = cell_area_ha,
  total_cells  = total_cells,
  suitable_cells = suitable_cells,
  suitable_ha    = round(suitable_cells * cell_area_ha, 1),
  suitable_pct   = pct_suitable,
  criteria = list(
    elevation    = criterion_summary(suit_elev),
    slope        = criterion_summary(suit_slope),
    aspect       = criterion_summary(suit_aspect),
    combined_and = criterion_summary(suitability)
  )
)
dir.create(dirname(out_report), recursive = TRUE, showWarnings = FALSE)
write_json(report, out_report, auto_unbox = TRUE, pretty = TRUE)
message("Saved report: ", out_report)

# =============================================================================
# EXPORT
# =============================================================================

writeRaster(suitability, out_path, overwrite = TRUE, datatype = "INT1U")
message("Saved raster: ", out_path)

# Vectorize: dissolve cells with the same value into polygons
suit_vec <- as.polygons(suitability, dissolve = TRUE)
writeVector(suit_vec, out_vec_path, overwrite = TRUE)
message("Saved vector: ", out_vec_path)

