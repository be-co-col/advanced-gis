# =============================================================================
# SUITABILITY ANALYSIS — DEM TERRAIN + HYDROLOGY + SOLAR RADIATION (COMBINED)
# =============================================================================

rm(list = ls())
library(terra)
library(jsonlite)

# =============================================================================
# INPUTS
# =============================================================================

dem_path      <- "Data/DEM/RLP-DEM.tif"
streams_path  <- "Data/Session07/0_results/streams.gpkg"
global_path   <- "Data/Solar/grass/RLP/global.tif"
duration_path <- "Data/Solar/grass/RLP/duration.tif"

docs_repo_path <- file.path(Sys.getenv("HOME"), "Dev/advanced-gis")

# =============================================================================
# THRESHOLDS  (identical to suitability_analysis.R / hydro_suitability.R /
# solar_suitability.R — duplicated on purpose so each script stays
# self-contained and independently re-runnable)
# =============================================================================

elev_min <- 0
elev_max <- 260

slope_unit <- "percent"
slope_min  <- 10
slope_max  <- 55

aspect_min <- 112.5
aspect_max <- 247.5

frost_buffer_m <- 100   # cold-air-sink buffer, see hydro_suitability.R / [@poling2007]
min_class      <- 2     # relative radiation class cutoff, see solar_suitability.R / [@bois2008]

# =============================================================================
# OUTPUTS
# =============================================================================

out_dir           <- "Data/Suitability/"
dir.create(out_dir, showWarnings = FALSE)
out_full_combined <- file.path(out_dir, "suitability_full_combined.tif")
out_full_vec      <- file.path(out_dir, "suitability_full.gpkg")
out_full_removed_vec <- file.path(out_dir, "suitability_full_removed.gpkg")
out_report        <- file.path(docs_repo_path, "docs/assets/data/suitability/report_full.json")

# =============================================================================
# LOAD & PREPARE DEM
# =============================================================================

dem <- rast(dem_path)[[1]]

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
    suit_aspect <- (aspect >= aspect_min) | (aspect <= aspect_max)
  }
} else {
  suit_aspect <- dem * 0 + 1
}

suit_dem <- as.int(suit_elev & suit_slope & suit_aspect)

# =============================================================================
# HYDROLOGY SUITABILITY (FROST / COLD-AIR-SINK EXCLUSION)
# =============================================================================

streams <- vect(streams_path)
if (is.na(crs(streams)) || crs(streams) == "") {
  # streams.gpkg has no CRS recorded in the file itself — see hydro_suitability.R
  crs(streams) <- crs(dem)
} else if (!same.crs(streams, dem)) {
  streams <- project(streams, crs(dem))
}
frost_buffer_vec <- buffer(streams, width = frost_buffer_m)
frost_mask <- as.int(rasterize(frost_buffer_vec, dem, field = 1, background = 0))
suit_hydro_ok <- (frost_mask == 0)

# =============================================================================
# SOLAR SUITABILITY
# =============================================================================

global_r   <- rast(global_path)
duration_r <- rast(duration_path)
if (!compareGeom(global_r, dem, stopOnError = FALSE))   global_r   <- project(global_r,   dem, method = "bilinear")
if (!compareGeom(duration_r, dem, stopOnError = FALSE)) duration_r <- project(duration_r, dem, method = "bilinear")

# Regular-interval clustering (Bois et al., 2008) — see solar_suitability.R
relative_class <- function(r, n_classes = 3) {
  rng <- as.numeric(global(r, "range", na.rm = TRUE))
  classify(r, seq(rng[1], rng[2], length.out = n_classes + 1), include.lowest = TRUE)
}

suit_solar <- (relative_class(global_r) >= min_class) & (relative_class(duration_r) >= min_class)

# =============================================================================
# COMBINED SUITABILITY + INDEPENDENT / OVERLAPPING REMOVAL
#
# The two refinements are applied independently to the DEM baseline (not
# sequentially), so a cell can be removed by hydro alone, solar alone, or
# both at once — reporting the overlap separately shows how much the two
# refinements are catching the same ground vs. complementary ground.
# =============================================================================

suit_full <- as.int(suit_dem & suit_hydro_ok & suit_solar)
names(suit_full) <- "suitability_full"

removed_hydro_only <- as.int((suit_dem == 1L) & (!suit_hydro_ok) &  suit_solar)
removed_solar_only <- as.int((suit_dem == 1L) &  suit_hydro_ok  & (!suit_solar))
removed_both       <- as.int((suit_dem == 1L) & (!suit_hydro_ok) & (!suit_solar))
removed_full       <- as.int((suit_dem == 1L) & (suit_full == 0L))
names(removed_full) <- "removed_full"

# =============================================================================
# SUMMARY
# =============================================================================

count_dem          <- global(suit_dem,   "sum", na.rm = TRUE)[[1]]
count_full         <- global(suit_full,  "sum", na.rm = TRUE)[[1]]
count_hydro_only   <- global(removed_hydro_only, "sum", na.rm = TRUE)[[1]]
count_solar_only   <- global(removed_solar_only, "sum", na.rm = TRUE)[[1]]
count_both         <- global(removed_both,       "sum", na.rm = TRUE)[[1]]
count_full_removed <- global(removed_full,       "sum", na.rm = TRUE)[[1]]
total_cells        <- ncell(dem) - global(dem, fun = "isNA")[[1]]
cell_area_ha       <- (res(dem)[1] * res(dem)[2]) / 10000

message(sprintf("DEM-only suitable:       %s cells  (%.0f ha)",
  formatC(count_dem, format = "f", digits = 0, big.mark = ","), count_dem * cell_area_ha))
message(sprintf("Removed by hydro only:   %s cells  (%.0f ha, %.1f%%)",
  formatC(count_hydro_only, format = "f", digits = 0, big.mark = ","),
  count_hydro_only * cell_area_ha, count_hydro_only / count_dem * 100))
message(sprintf("Removed by solar only:   %s cells  (%.0f ha, %.1f%%)",
  formatC(count_solar_only, format = "f", digits = 0, big.mark = ","),
  count_solar_only * cell_area_ha, count_solar_only / count_dem * 100))
message(sprintf("Removed by both:         %s cells  (%.0f ha, %.1f%%)",
  formatC(count_both, format = "f", digits = 0, big.mark = ","),
  count_both * cell_area_ha, count_both / count_dem * 100))
message(sprintf("Fully combined suitable: %s cells  (%.0f ha)",
  formatC(count_full, format = "f", digits = 0, big.mark = ","), count_full * cell_area_ha))
message(sprintf("Refinements removed %.1f%% of DEM-suitable area in total.",
  count_full_removed / count_dem * 100))

# =============================================================================
# JSON REPORT
# =============================================================================

report <- list(
  label          = "Combined model (DEM + hydro + solar)",
  script         = "full_suitability.R",
  generated_at   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  cell_area_ha   = cell_area_ha,
  total_cells    = total_cells,
  suitable_cells = count_full,
  suitable_ha    = round(count_full * cell_area_ha, 1),
  suitable_pct   = round(count_full / total_cells * 100, 1),
  baseline_suitable_cells = count_dem,
  baseline_suitable_ha    = round(count_dem * cell_area_ha, 1),
  removed_cells  = count_full_removed,
  removed_ha     = round(count_full_removed * cell_area_ha, 1),
  removed_pct    = round(count_full_removed / count_dem * 100, 1),
  refinements = list(
    hydro_only = list(
      removed_cells = count_hydro_only,
      removed_ha    = round(count_hydro_only * cell_area_ha, 1),
      removed_pct   = round(count_hydro_only / count_dem * 100, 1)
    ),
    solar_only = list(
      removed_cells = count_solar_only,
      removed_ha    = round(count_solar_only * cell_area_ha, 1),
      removed_pct   = round(count_solar_only / count_dem * 100, 1)
    ),
    both = list(
      removed_cells = count_both,
      removed_ha    = round(count_both * cell_area_ha, 1),
      removed_pct   = round(count_both / count_dem * 100, 1)
    )
  )
)
dir.create(dirname(out_report), recursive = TRUE, showWarnings = FALSE)
write_json(report, out_report, auto_unbox = TRUE, pretty = TRUE)
message("Saved report: ", out_report)

# =============================================================================
# EXPORT
# =============================================================================

writeRaster(suit_full, out_full_combined, overwrite = TRUE, datatype = "INT1U")

suit_full_vec <- as.polygons(suit_full, dissolve = TRUE)
writeVector(suit_full_vec, out_full_vec, overwrite = TRUE)

# Vectorized for the webmap: area cut by either refinement (red) alongside
# the resulting suitable area above (green)
removed_full_vec <- as.polygons(removed_full, dissolve = TRUE)
writeVector(removed_full_vec, out_full_removed_vec, overwrite = TRUE)

message("Saved: ", out_full_combined)
message("Saved: ", out_full_vec)
message("Saved: ", out_full_removed_vec)
