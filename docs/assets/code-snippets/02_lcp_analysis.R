# =============================================================================
# LEAST COST PATH ANALYSIS: Frodo's path from Hobbiton to Mt. Doom
# Requires outputs from 01_preprocessing.R in out_dir
# =============================================================================

rm(list = ls())

library(terra)
library(sf)
library(whitebox)
wbt_init()  # downloads the WhiteboxTools binary on first run

# =============================================================================
# Paths
# =============================================================================
vector_dir <- "Session10/Arda/data/vectors"
out_dir    <- "Session10/Arda/data/output"

CRS_ARDA <- "EPSG:32631"

cost_file     <- file.path(out_dir, "cost_rate_raw_min_per_m.tif")
source_file   <- file.path(out_dir, "source_cell.tif")
dest_file     <- file.path(out_dir, "dest_cell.tif")
accum_file    <- file.path(out_dir, "cost_distance.tif")
backlink_file <- file.path(out_dir, "cost_backlink.tif")
lcp_file      <- file.path(out_dir, "least_cost_path.tif")

# =============================================================================
# Step 2a: Write source and destination as single-cell rasters
# =============================================================================
source_sf <- st_transform(st_read(file.path(vector_dir, "source_layer.gpkg"), quiet = TRUE), CRS_ARDA)
dest_sf   <- st_transform(st_read(file.path(vector_dir, "dest_layer.gpkg"),   quiet = TRUE), CRS_ARDA)

template_disk <- rast(cost_file)

write_point_raster <- function(xy, template, filename) {
  cell <- cellFromXY(template, matrix(xy, ncol = 2))
  r    <- rowFromCell(template, cell)
  co   <- colFromCell(template, cell)
  nr   <- nrow(template)
  nc   <- ncol(template)
  out  <- rast(template)
  writeStart(out, filename, overwrite = TRUE, datatype = "FLT4S")
  na_row <- matrix(NA_real_, nrow = 1, ncol = nc)
  for (i in seq_len(nr)) {
    row_data <- na_row
    if (i == r) row_data[co] <- 1.0
    writeValues(out, row_data, start = i, nrows = 1)
  }
  writeStop(out)
}

write_point_raster(crds(vect(source_sf)), template_disk, source_file)
write_point_raster(crds(vect(dest_sf)),   template_disk, dest_file)

# =============================================================================
# Step 2b: Cost Distance + Backlink
# =============================================================================
wbt_cost_distance(
  source       = source_file,
  cost         = cost_file,
  out_accum    = accum_file,
  out_backlink = backlink_file
)

# =============================================================================
# Step 3: Least Cost Path (raster)
# =============================================================================
wbt_cost_pathway(
  destination     = dest_file,
  backlink        = backlink_file,
  output          = lcp_file,
  zero_background = FALSE
)

cat("LCP analysis done. Outputs in:", out_dir, "\n")
cat("  source_cell.tif / dest_cell.tif\n")
cat("  cost_distance.tif       – accumulated cost from Hobbiton\n")
cat("  cost_backlink.tif       – backlink directions (1–8)\n")
cat("  least_cost_path.tif     – optimal path (raster, load in QGIS to vectorize)\n")
