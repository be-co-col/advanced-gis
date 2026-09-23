# =============================================================================
# HYDROLOGICAL ANALYSIS: FILLED DEM → FLOW DIR → FLOW ACC → WATERSHED
# =============================================================================

# =============================================================================
# CLEAN ENVIRONMENT AND LOAD LIBRARIES
# =============================================================================

rm(list = ls())

library(whitebox)
library(terra)

wbt_init()  # downloads WhiteboxTools binaries on first run

# =============================================================================
# PATHS
# =============================================================================

dem_path       <- "Session07/data/DEM/RLP-DEM.tif"
out_dir        <- "Session07/results"

# Created in QGIS after inspecting the accumulation raster.
# Leave as NA for the first run — the script will stop after producing
# the accumulation raster so you can define the pour point.
pour_point_path <- "Session07/data/pour-point.gpkg"

# Snapping distance (map units = metres): moves the pour point to the nearest
# high-accumulation cell within this radius.
snap_dist <- 150

# Minimum number of upstream cells to be classified as a stream.
# Lower = denser network; higher = only major channels.
stream_threshold <- 5000

# =============================================================================
# SETUP
# =============================================================================

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

out_dir_abs  <- normalizePath(out_dir, mustWork = TRUE)

# Whitebox needs a single-band file — strip extra bands if present
dem_raw <- rast(dem_path)
if (nlyr(dem_raw) > 1) {
  message("Multi-band DEM detected — extracting band 1 for whitebox.")
  dem_raw <- dem_raw[[1]]
}
dem_single_path <- file.path(out_dir_abs, "dem_single_band.tif")
writeRaster(dem_raw, dem_single_path, overwrite = TRUE)
dem_abs <- normalizePath(dem_single_path, mustWork = TRUE)

filled_path      <- file.path(out_dir_abs, "dem_filled.tif")
flowdir_path     <- file.path(out_dir_abs, "flowdir_d8.tif")
flowacc_path     <- file.path(out_dir_abs, "flowacc_d8.tif")
stream_rast_path <- file.path(out_dir_abs, "streams.tif")
stream_shp_path  <- file.path(out_dir_abs, "streams.shp")
stream_vec_path  <- file.path(out_dir_abs, "streams.gpkg")

# =============================================================================
# STEP 1: FILL SINKS (hydrologically conditioned DEM)
# =============================================================================

wbt_fill_depressions_wang_and_liu(
  dem    = dem_abs,
  output = filled_path
)
message("Filled DEM saved: ", filled_path)

# =============================================================================
# STEP 2: D8 FLOW DIRECTION
# =============================================================================

wbt_d8_pointer(
  dem    = filled_path,
  output = flowdir_path
)
message("D8 flow direction saved: ", flowdir_path)

# =============================================================================
# STEP 3: D8 FLOW ACCUMULATION
# =============================================================================

wbt_d8_flow_accumulation(
  input  = filled_path,
  output = flowacc_path
)
message("D8 flow accumulation saved: ", flowacc_path)

# =============================================================================
# STEP 4: STREAM NETWORK
# =============================================================================

# Threshold accumulation to binary stream raster
wbt_extract_streams(
  flow_accum = flowacc_path,
  output     = stream_rast_path,
  threshold  = stream_threshold
)

# Vectorize to lines (whitebox outputs SHP only)
wbt_raster_streams_to_vector(
  streams = stream_rast_path,
  d8_pntr = flowdir_path,
  output  = stream_shp_path
)

# Sample accumulation at each segment's downstream endpoint for QGIS width styling.
# Accumulation increases monotonically downstream, so the last vertex of each
# segment always holds the maximum — point extraction is fast and accurate.
streams  <- vect(stream_shp_path)
flowacc  <- rast(flowacc_path)

coords    <- as.data.frame(geom(streams))
last_pts  <- coords[!duplicated(coords$geom, fromLast = TRUE), ]
end_vect  <- vect(last_pts, geom = c("x", "y"), crs = crs(streams))

acc_vals        <- extract(flowacc, end_vect)
streams$max_accum <- acc_vals[, 2]

writeVector(streams, stream_vec_path, overwrite = TRUE)
message("Stream network saved: ", stream_vec_path)

# =============================================================================
# STOP HERE — define pour point in QGIS
# -----------------------------------------------------------------------------
# 1. Load ", flowacc_path, " in QGIS.
# 2. Create a new GeoPackage layer with a single point at desired outlet.
#    (Layer > Create Layer > New GeoPackage Layer, geometry type: Point,
#     same CRS as the DEM)
# 3. Set pour_point_path at the top of this script to that file's path.
# 4. Re-run the script — it will continue below.
# =============================================================================

if (is.na(pour_point_path)) {
  message(
    "\nDone with terrain preprocessing.\n",
    "Now create a pour point in QGIS and set 'pour_point_path' at the top,\n",
    "then re-run the script to delineate the watershed."
  )
  stop("Waiting for pour point — see instructions above.", call. = FALSE)
}

# =============================================================================
# STEP 4: SNAP POUR POINT TO STREAM
# =============================================================================

# wbt_snap_pour_points only accepts Shapefiles — convert GPKG first
pp_shp_path <- file.path(out_dir_abs, "pour_point_input.shp")
writeVector(vect(pour_point_path), pp_shp_path, overwrite = TRUE)
pp_abs <- normalizePath(pp_shp_path, mustWork = TRUE)

snapped_path <- file.path(out_dir_abs, "pour_point_snapped.shp")

wbt_snap_pour_points(
  pour_pts   = pp_abs,
  flow_accum = flowacc_path,
  output     = snapped_path,
  snap_dist  = snap_dist
)
message("Snapped pour point saved: ", snapped_path)

# =============================================================================
# STEP 5: WATERSHED DELINEATION
# =============================================================================

watershed_rast_path <- file.path(out_dir_abs, "watershed.tif")

wbt_watershed(
  d8_pntr  = flowdir_path,
  pour_pts = snapped_path,
  output   = watershed_rast_path
)
message("Watershed raster saved: ", watershed_rast_path)

# =============================================================================
# STEP 6: VECTORIZE WATERSHED
# =============================================================================

watershed_vec_path <- file.path(out_dir_abs, "watershed.gpkg")

ws     <- rast(watershed_rast_path)
ws_vec <- as.polygons(ws, dissolve = TRUE)
writeVector(ws_vec, watershed_vec_path, overwrite = TRUE)
message("Watershed polygon saved: ", watershed_vec_path)
