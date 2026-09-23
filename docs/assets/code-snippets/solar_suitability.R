# =============================================================================
# SUITABILITY ANALYSIS — DEM TERRAIN + SOLAR RADIATION + SUN DURATION
# =============================================================================

rm(list = ls())
library(terra)
library(jsonlite)

# =============================================================================
# INPUTS
# =============================================================================

dem_path      <- "Data/DEM/RLP-DEM.tif"              # band 1 = elevation
global_path   <- "Data/Solar/grass/RLP/global.tif"   # growing-season (Apr-Oct) global radiation (Wh/m²)
duration_path <- "Data/Solar/grass/RLP/duration.tif" # growing-season (Apr-Oct) sun duration (h)

docs_repo_path <- file.path(Sys.getenv("HOME"), "Dev/advanced-gis")

# =============================================================================
# THRESHOLDS
# =============================================================================

# Elevation (metres)
elev_min <- 0
elev_max <- 260

# Slope
slope_unit <- "percent"   # "degrees" or "percent"
slope_min  <- 10
slope_max  <- 55

# Aspect (degrees, 0–360 clockwise from N; set either to NA to skip)
aspect_min <- 112.5   # SE
aspect_max <- 247.5   # SW

# Solar: there is no portable absolute Wh/m² or hour threshold in the
# viticulture literature for clear-sky modelled radiation (see Bois et al.,
# 2008, J. Int. Sci. Vigne Vin 42(1), 15-25) — comparable studies classify a
# study area's *own* radiation values into low/medium/high via regular-
# interval clustering (equal-width bins spanning the observed min-max)
# instead. min_class selects which of those 3 classes count as "suitable":
# 1 = low, 2 = medium, 3 = high; min_class = 2 keeps medium + high.
min_class <- 2

# =============================================================================
# OUTPUTS
# =============================================================================

out_dir         <- "Data/Solar/grass/RLP/"
out_dem_suit    <- file.path(out_dir, "suitability_dem.tif")
out_solar_suit  <- file.path(out_dir, "suitability_solar.tif")
out_combined    <- file.path(out_dir, "suitability_combined.tif")
out_diff        <- file.path(out_dir, "suitability_diff.tif")  # 1 = removed by solar filter
out_combined_vec <- file.path(out_dir, "suitability_combined.gpkg")
out_diff_vec      <- file.path(out_dir, "suitability_diff.gpkg")
out_report      <- file.path(docs_repo_path, "docs/assets/data/suitability/report_solar.json")

# =============================================================================
# LOAD & PREPARE DEM
# =============================================================================

dem <- rast(dem_path)[[1]]   # band 1 only

slope  <- terrain(dem, v = "slope",  unit = "degrees")
if (slope_unit == "percent") slope <- tan(slope * pi / 180) * 100
aspect <- terrain(dem, v = "aspect", unit = "degrees")

# =============================================================================
# DEM-BASED SUITABILITY
# =============================================================================

suit_elev  <- (dem   >= elev_min) & (dem   <= elev_max)
suit_slope <- (slope >= slope_min) & (slope <= slope_max)

if (!is.na(aspect_min) && !is.na(aspect_max)) {
  if (aspect_min <= aspect_max) {
    suit_aspect <- (aspect >= aspect_min) & (aspect <= aspect_max)
  } else {
    # wrap-around (e.g. 315–45°, crosses north)
    suit_aspect <- (aspect >= aspect_min) | (aspect <= aspect_max)
  }
} else {
  suit_aspect <- dem * 0 + 1
}

suit_dem <- as.int(suit_elev & suit_slope & suit_aspect)
names(suit_dem) <- "suitability_dem"

# =============================================================================
# SOLAR SUITABILITY
# =============================================================================

global_r   <- rast(global_path)
duration_r <- rast(duration_path)

# Reproject solar rasters to DEM grid if needed
if (!compareGeom(global_r, dem, stopOnError = FALSE)) {
  global_r <- project(global_r, dem, method = "bilinear")
}
if (!compareGeom(duration_r, dem, stopOnError = FALSE)) {
  duration_r <- project(duration_r, dem, method = "bilinear")
}

# Regular-interval clustering (Bois et al., 2008): classify each raster into
# n_classes equal-width bins spanning its own observed range.
relative_class <- function(r, n_classes = 3) {
  rng <- as.numeric(global(r, "range", na.rm = TRUE))
  classify(r, seq(rng[1], rng[2], length.out = n_classes + 1), include.lowest = TRUE)
}

suit_global   <- relative_class(global_r)   >= min_class
suit_duration <- relative_class(duration_r) >= min_class

suit_solar <- as.int(suit_global & suit_duration)
names(suit_solar) <- "suitability_solar"

# =============================================================================
# COMBINED SUITABILITY
# =============================================================================

suit_combined <- as.int(suit_dem & suit_solar)
names(suit_combined) <- "suitability_combined"

# =============================================================================
# DIFF: areas removed by the solar filter
# 1 = was suitable (DEM only) but removed by solar constraints
# 0 = no change (not suitable before, or still suitable)
# =============================================================================

suit_diff <- as.int((suit_dem == 1L) & (suit_combined == 0L))
names(suit_diff) <- "removed_by_solar"

# =============================================================================
# SUMMARY
# =============================================================================

count_dem      <- global(suit_dem,      "sum", na.rm = TRUE)[[1]]
count_combined <- global(suit_combined, "sum", na.rm = TRUE)[[1]]
count_removed  <- global(suit_diff,     "sum", na.rm = TRUE)[[1]]
cell_area_ha   <- (res(dem)[1] * res(dem)[2]) / 10000

message(sprintf("DEM-only suitable:      %s cells  (%.0f ha)",
  formatC(count_dem,      format = "f", digits = 0, big.mark = ","),
  count_dem      * cell_area_ha))
message(sprintf("Combined suitable:      %s cells  (%.0f ha)",
  formatC(count_combined, format = "f", digits = 0, big.mark = ","),
  count_combined * cell_area_ha))
message(sprintf("Removed by solar mask:  %s cells  (%.0f ha)",
  formatC(count_removed,  format = "f", digits = 0, big.mark = ","),
  count_removed  * cell_area_ha))
message(sprintf("Solar filter removed %.1f%% of DEM-suitable area.",
  count_removed / count_dem * 100))

# =============================================================================
# JSON REPORT
# =============================================================================

total_cells <- ncell(dem) - global(dem, fun = "isNA")[[1]]

report <- list(
  label          = "Solar refinement",
  script         = "solar_suitability.R",
  generated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  cell_area_ha   = cell_area_ha,
  total_cells    = total_cells,
  suitable_cells = count_combined,
  suitable_ha    = round(count_combined * cell_area_ha, 1),
  suitable_pct   = round(count_combined / total_cells * 100, 1),
  baseline_suitable_cells = count_dem,
  baseline_suitable_ha    = round(count_dem * cell_area_ha, 1),
  removed_cells  = count_removed,
  removed_ha     = round(count_removed * cell_area_ha, 1),
  removed_pct    = round(count_removed / count_dem * 100, 1)
)
dir.create(dirname(out_report), recursive = TRUE, showWarnings = FALSE)
write_json(report, out_report, auto_unbox = TRUE, pretty = TRUE)
message("Saved report: ", out_report)

# =============================================================================
# EXPORT
# =============================================================================

writeRaster(suit_dem,      out_dem_suit,   overwrite = TRUE, datatype = "INT1U")
writeRaster(suit_solar,    out_solar_suit, overwrite = TRUE, datatype = "INT1U")
writeRaster(suit_combined, out_combined,   overwrite = TRUE, datatype = "INT1U")
writeRaster(suit_diff,     out_diff,       overwrite = TRUE, datatype = "INT1U")

# Vectorized for the webmap: resulting suitable area (green) + area cut by
# the solar filter (red)
writeVector(as.polygons(suit_combined, dissolve = TRUE), out_combined_vec, overwrite = TRUE)
writeVector(as.polygons(suit_diff,     dissolve = TRUE), out_diff_vec,     overwrite = TRUE)

message("Saved: ", out_dem_suit)
message("Saved: ", out_solar_suit)
message("Saved: ", out_combined)
message("Saved: ", out_diff)
message("Saved: ", out_combined_vec)
message("Saved: ", out_diff_vec)
