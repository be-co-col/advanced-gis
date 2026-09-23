# =============================================================================
# SOLAR RADIATION ANALYSIS — GRASS r.sun via rgrass
# Apr 1 – Oct 31 growing season, RLP study area
# =============================================================================

system.time({

rm(list = ls())

library(terra)
library(rgrass)   # GRASS bridge — requires GRASS GIS to be installed

# =============================================================================
# PATHS
# =============================================================================

dem_path  <- "Data/DEM/RLP-DEM.tif"
suit_path <- "Data/Session05/results/RLP-suitability.tif"
out_dir   <- "Data/Solar/grass/RLP/"
dir.create(out_dir, showWarnings = FALSE)

# =============================================================================
# LOAD DATA
# =============================================================================

dem_raw  <- rast(dem_path)[[1]]   # band 1 only (multi-band DEM)
suit_raw <- rast(suit_path)[[1]]  # binary 0/1 suitability mask, band 1

# =============================================================================
# INITIALISE GRASS IN A TEMPORARY LOCATION
# =============================================================================

gisBase <- trimws(system("grass --config path", intern = TRUE))

td       <- file.path(tempdir(), "solar_grassdb")
loc_path <- file.path(td, "solar_project")

# Remove any stale location from a previous run (no CRS means imports fail)
unlink(loc_path, recursive = TRUE)
dir.create(td, recursive = TRUE, showWarnings = FALSE)

# Create a fresh GRASS location whose CRS is stamped from the DEM file.
# Using -c <raster> is the canonical way to inherit CRS in GRASS 8.x.
system2("grass", c("--text", "-c", normalizePath(dem_path), loc_path, "--exec", "exit"),
        stdout = FALSE, stderr = FALSE)

initGRASS(
  gisBase  = gisBase,
  home     = td,
  gisDbase = td,
  location = "solar_project",
  mapset   = "PERMANENT",
  override = TRUE
)

# Import band 1 of each TIF directly via r.in.gdal (write_RAST would import all
# bands and name them dem.1 / dem.alpha, which breaks downstream module calls)
execGRASS("r.in.gdal",
  flags  = "overwrite",
  input  = normalizePath(dem_path),
  output = "dem",
  band   = 1
)
execGRASS("r.in.gdal",
  flags  = "overwrite",
  input  = normalizePath(suit_path),
  output = "suit",
  band   = 1
)
execGRASS("g.region", raster = "dem", flags = "p")

# =============================================================================
# STEP 1: TERRAIN DERIVATIVES
# r.sun needs slope and aspect derived from the DEM.
# GRASS convention: slope in degrees, aspect in degrees clockwise from north.
# =============================================================================

execGRASS("r.slope.aspect",
  flags     = "overwrite",
  elevation = "dem",
  slope     = "slope",
  aspect    = "aspect"
)

# =============================================================================
# STEP 2: SOLAR RADIATION LOOP  (April 1 – October 31) — parallelised
#
# r.sun models one day at a time; each day is independent so we distribute
# them across cores. GRASS locks the whole mapset for writes, so each worker
# gets its own temporary mapset that reads shared inputs from PERMANENT.
# =============================================================================

day_start <- as.integer(format(as.Date("2025-04-01"), "%j"))  # DOY 91
day_end   <- as.integer(format(as.Date("2025-10-31"), "%j"))  # DOY 304
day_step  <- 5    # every 5 days — reduce to 1 for maximum accuracy (slower)
linke     <- 3.0

days    <- seq(day_start, day_end, by = day_step)
n_cores <- min(parallel::detectCores() - 1L, length(days))
batches <- split(days, (seq_along(days) - 1L) %% n_cores)

message(sprintf("Running r.sun for %d days across %d workers …", length(days), n_cores))

# Create one mapset per worker (must happen before forking)
worker_mapsets <- sprintf("rsun_worker_%02d", seq_along(batches))
for (ms in worker_mapsets) {
  execGRASS("g.mapset", flags = "c", mapset = ms)
}
execGRASS("g.mapset", mapset = "PERMANENT")  # switch back before fork

# Write a GISRC file per worker before forking. initGRASS() inside forked
# workers calls tempfile() and Sys.setenv(), but all workers inherit the same
# RNG seed so tempfile() generates colliding paths that overwrite each other's
# session. Writing the files here and passing their paths avoids that.
worker_gisrc <- vapply(seq_along(batches), function(wi) {
  f <- file.path(td, sprintf("gisrc_worker_%02d", wi))
  writeLines(c(
    paste("GISDBASE:", td),
    "LOCATION_NAME: solar_project",
    paste("MAPSET:", worker_mapsets[wi]),
    "GUI: text"
  ), f)
  f
}, character(1))

parallel::mclapply(seq_along(batches), function(wi) {
  Sys.setenv(GISRC = worker_gisrc[wi])
  for (d in batches[[wi]]) {
    execGRASS("r.sun",
      flags       = "overwrite",
      elevation   = "dem@PERMANENT",
      slope       = "slope@PERMANENT",
      aspect      = "aspect@PERMANENT",
      day         = d,
      step        = 0.5,
      linke_value = linke,
      beam_rad    = sprintf("beam_%03d",  d),
      diff_rad    = sprintf("diff_%03d",  d),
      glob_rad    = sprintf("glob_%03d",  d),
      insol_time  = sprintf("insol_%03d", d)
    )
  }
  invisible(NULL)
}, mc.cores = n_cores)

# Parent GISRC is unchanged by the fork. Add worker mapsets to PERMANENT's
# search path so r.series can find beam_*/diff_*/glob_*/insol_* without
# @mapset suffixes. Note: -s opens a GUI in GRASS 8.x; use operation= instead.
execGRASS("g.mapsets", operation = "add", mapset = paste(worker_mapsets, collapse = ","))

# =============================================================================
# STEP 3: SUM OVER GROWING SEASON  (r.series) THEN SCALE BY day_step
# =============================================================================

fmt_list <- function(prefix)
  paste(sprintf("%s_%03d", prefix, days), collapse = ",")

for (var in c("beam", "diff", "glob", "insol")) {
  execGRASS("r.series",
    flags  = "overwrite",
    input  = fmt_list(var),
    output = paste0(var, "_sum"),
    method = "sum"
  )
  # Each sampled day represents day_step actual days in the season
  execGRASS("r.mapcalc",
    flags      = "overwrite",
    expression = sprintf("%s_total = %s_sum * %d", var, var, day_step)
  )
}

# =============================================================================
# STEP 4: CONTIGUOUS SUITABLE PATCHES  (r.clump = "Region Group")
# Null out unsuitable pixels first so only suitable cells get a patch ID.
# =============================================================================

execGRASS("r.mapcalc",
  flags      = "overwrite",
  expression = "suit_only = if(suit == 1, 1, null())"
)

execGRASS("r.clump",
  flags  = "overwrite",
  input  = "suit_only",
  output = "patches"
)

# =============================================================================
# STEP 5: EXPORT TO R / GEOTIFF
# read_RAST() uses the RRASTER format which fails for Float64 maps with many
# unique values. Export directly to GeoTIFF via r.out.gdal instead.
# =============================================================================

grass_to_tif <- function(grass_name, out_path, type = "Float64") {
  execGRASS("r.out.gdal",
    flags  = c("overwrite", "c", "m"),
    input  = grass_name,
    output = normalizePath(out_path, mustWork = FALSE),
    format = "GTiff",
    type   = type
  )
  rast(out_path)
}

direct_r   <- grass_to_tif("beam_total",  file.path(out_dir, "direct.tif"))
diffuse_r  <- grass_to_tif("diff_total",  file.path(out_dir, "diffuse.tif"))
global_r   <- grass_to_tif("glob_total",  file.path(out_dir, "global.tif"))
duration_r <- grass_to_tif("insol_total", file.path(out_dir, "duration.tif"))
patches_r  <- grass_to_tif("patches",     file.path(out_dir, "patches.tif"), type = "Int32")

# =============================================================================
# STEP 6: ZONAL STATISTICS (mean per patch)
# =============================================================================

zs <- function(r, nm) setNames(zonal(r, patches_r, "mean", na.rm = TRUE), c("patch", nm))

z <- Reduce(
  function(a, b) merge(a, b, by = "patch"),
  list(
    zs(direct_r,   "mean_direct"),
    zs(diffuse_r,  "mean_diffuse"),
    zs(global_r,   "mean_global"),
    zs(duration_r, "mean_duration")
  )
)
print(z)

# Drop patches where all radiation cells were NULL (edge artefacts of r.clump
# on small 1-2 pixel clumps that fall entirely within DEM nodata cells)
z <- z[!is.nan(z$mean_global), ]

# =============================================================================
# STEP 7: CLASSIFY PATCHES BY RELATIVE RADIATION LEVEL
#
# There is no portable absolute Wh/m² threshold in the viticulture literature
# for clear-sky modelled radiation (see Bois et al., 2008, J. Int. Sci. Vigne
# Vin 42(1), 15-25) — comparable studies classify a study area's *own*
# radiation values into low/medium/high using regular-interval clustering
# (equal-width bins spanning the observed min-max), not an externally sourced
# cutoff. These classes are therefore relative to this study area only and
# are not meant to be reused elsewhere.
# =============================================================================

rad_breaks <- seq(min(z$mean_global, na.rm = TRUE), max(z$mean_global, na.rm = TRUE), length.out = 4)

z$rad_class <- cut(
  z$mean_global,
  breaks = rad_breaks,
  labels = c("low", "medium", "high"),
  include.lowest = TRUE
)

# Vectorise patches and join statistics.
# as.polygons()[[1]] on a 0-row SpatVector returns NA (not integer(0)), so
# using explicit integer coercion and index-based subsetting to stay safe.
patches_poly <- as.polygons(patches_r, dissolve = TRUE)
patch_ids    <- as.integer(values(patches_poly)[, 1])
keep_idx     <- which(!is.na(patch_ids) & patch_ids %in% z$patch)
patches_poly <- patches_poly[keep_idx, ]
idx <- match(as.integer(values(patches_poly)[, 1]), z$patch)
patches_poly$mean_global   <- z$mean_global[idx]
patches_poly$mean_duration <- z$mean_duration[idx]
patches_poly$rad_class     <- as.character(z$rad_class[idx])

# =============================================================================
# STEP 8: MAP
# =============================================================================

library(tmap)
tmap_mode("plot")

map_radiation <- tm_shape(patches_poly) +
  tm_polygons(
    fill       = "mean_global",
    fill.scale = tm_scale_intervals(values = "YlOrRd", style = "quantile"),
    fill.legend = tm_legend(title = "Global Radiation (Wh/m²)\nApr–Oct 2025"),
    col        = "grey40",
    lwd        = 0.4
  ) +
  tm_title("Global Radiation\n(GRASS r.sun via rgrass)")

map_class <- tm_shape(patches_poly) +
  tm_polygons(
    fill       = "rad_class",
    fill.scale = tm_scale_categorical(
      values = c(low = "#4575b4", medium = "#ffffbf", high = "#d73027")
    ),
    fill.legend = tm_legend(title = "Radiation zone (relative)"),
    col        = "grey40",
    lwd        = 0.4
  ) +
  tm_title("Global Radiation — Relative Zoning\n(regular-interval clustering, per Bois et al. 2008)")

print(tmap_arrange(map_radiation, map_class, ncol = 2))

})
