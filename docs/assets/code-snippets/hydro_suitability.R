# =============================================================================
# SUITABILITY ANALYSIS — DEM TERRAIN + HYDROLOGY (COLD-AIR-SINK / FROST RISK)
# =============================================================================

rm(list = ls())
library(terra)
library(jsonlite)

# =============================================================================
# INPUTS
# =============================================================================

dem_path     <- "Data/DEM/RLP-DEM.tif"                  # band 1 = elevation
streams_path <- "Data/Session07/0_results/streams.gpkg" # extracted network (>=5000 upstream cells, see hydro.R)

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

# Hydrology: cold-air-sink / frost-corridor buffer around the stream network
# (metres)
frost_buffer_m <- 100

# =============================================================================
# OUTPUTS
# =============================================================================

out_dir            <- "Data/Suitability/"
dir.create(out_dir, showWarnings = FALSE)
out_dem_suit       <- file.path(out_dir, "suitability_dem.tif")
out_frost_buffer   <- file.path(out_dir, "frost_buffer.gpkg")
out_hydro_combined <- file.path(out_dir, "suitability_hydro_combined.tif")
out_hydro_diff     <- file.path(out_dir, "suitability_hydro_diff.tif")
out_hydro_combined_vec <- file.path(out_dir, "suitability_hydro_combined.gpkg")
out_hydro_diff_vec     <- file.path(out_dir, "suitability_hydro_diff.gpkg")
out_report         <- file.path(docs_repo_path, "docs/assets/data/suitability/report_hydro.json")

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
# HYDROLOGY SUITABILITY (FROST / COLD-AIR-SINK EXCLUSION)
# =============================================================================

streams <- vect(streams_path)
if (is.na(crs(streams)) || crs(streams) == "") {
  # streams.gpkg has no CRS recorded in the file itself assign it directly
  # rather than reprojecting from nothing
  crs(streams) <- crs(dem)
} else if (!same.crs(streams, dem)) {
  streams <- project(streams, crs(dem))
}

frost_buffer_vec <- aggregate(buffer(streams, width = frost_buffer_m))
writeVector(frost_buffer_vec, out_frost_buffer, overwrite = TRUE)

frost_mask <- as.int(rasterize(frost_buffer_vec, dem, field = 1, background = 0))
names(frost_mask) <- "frost_buffer"

suit_hydro_combined <- as.int(suit_dem & (frost_mask == 0))
names(suit_hydro_combined) <- "suitability_hydro_combined"

# =============================================================================
# DIFF: areas removed by the frost buffer
# 1 = was suitable (DEM only) but removed by the frost-corridor exclusion
# 0 = no change (not suitable before, or still suitable)
# =============================================================================

suit_hydro_diff <- as.int((suit_dem == 1L) & (suit_hydro_combined == 0L))
names(suit_hydro_diff) <- "removed_by_hydro"

# =============================================================================
# SUMMARY
# =============================================================================

count_dem      <- global(suit_dem,            "sum", na.rm = TRUE)[[1]]
count_combined <- global(suit_hydro_combined, "sum", na.rm = TRUE)[[1]]
count_removed  <- global(suit_hydro_diff,     "sum", na.rm = TRUE)[[1]]
total_cells    <- ncell(dem) - global(dem, fun = "isNA")[[1]]
cell_area_ha   <- (res(dem)[1] * res(dem)[2]) / 10000

message(sprintf("DEM-only suitable:       %s cells  (%.0f ha)",
  formatC(count_dem,      format = "f", digits = 0, big.mark = ","),
  count_dem      * cell_area_ha))
message(sprintf("Hydro-combined suitable: %s cells  (%.0f ha)",
  formatC(count_combined, format = "f", digits = 0, big.mark = ","),
  count_combined * cell_area_ha))
message(sprintf("Removed by frost buffer: %s cells  (%.0f ha)",
  formatC(count_removed,  format = "f", digits = 0, big.mark = ","),
  count_removed  * cell_area_ha))
message(sprintf("Frost buffer removed %.1f%% of DEM-suitable area.",
  count_removed / count_dem * 100))

# =============================================================================
# JSON REPORT
# =============================================================================

suitability_report <- function(label, script, suitable_cells, total_cells, cell_area_ha,
                                baseline_cells = NULL, removed_cells = NULL) {
  report <- list(
    label          = label,
    script         = script,
    generated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    cell_area_ha   = cell_area_ha,
    total_cells    = total_cells,
    suitable_cells = suitable_cells,
    suitable_ha    = round(suitable_cells * cell_area_ha, 1),
    suitable_pct   = round(suitable_cells / total_cells * 100, 1)
  )
  if (!is.null(baseline_cells)) {
    report$baseline_suitable_cells <- baseline_cells
    report$baseline_suitable_ha    <- round(baseline_cells * cell_area_ha, 1)
    report$removed_cells           <- removed_cells
    report$removed_ha              <- round(removed_cells * cell_area_ha, 1)
    report$removed_pct             <- round(removed_cells / baseline_cells * 100, 1)
  }
  report
}

report <- suitability_report(
  label = "Hydrology (frost) refinement", script = "hydro_suitability.R",
  suitable_cells = count_combined, total_cells = total_cells, cell_area_ha = cell_area_ha,
  baseline_cells = count_dem, removed_cells = count_removed
)
dir.create(dirname(out_report), recursive = TRUE, showWarnings = FALSE)
write_json(report, out_report, auto_unbox = TRUE, pretty = TRUE)
message("Saved report: ", out_report)

# =============================================================================
# EXPORT
# =============================================================================

writeRaster(suit_dem,            out_dem_suit,       overwrite = TRUE, datatype = "INT1U")
writeRaster(suit_hydro_combined, out_hydro_combined, overwrite = TRUE, datatype = "INT1U")
writeRaster(suit_hydro_diff,     out_hydro_diff,     overwrite = TRUE, datatype = "INT1U")

# Vectorized for the webmap: resulting suitable area (green) + area cut by
# the frost buffer (red) — see suitability-model.md, section 2.
writeVector(as.polygons(suit_hydro_combined, dissolve = TRUE), out_hydro_combined_vec, overwrite = TRUE)
writeVector(as.polygons(suit_hydro_diff,     dissolve = TRUE), out_hydro_diff_vec,     overwrite = TRUE)

message("Saved: ", out_dem_suit)
message("Saved: ", out_hydro_combined)
message("Saved: ", out_hydro_diff)
message("Saved: ", out_frost_buffer)
message("Saved: ", out_hydro_combined_vec)
message("Saved: ", out_hydro_diff_vec)
