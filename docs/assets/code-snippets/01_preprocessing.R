# =============================================================================
# PREPROCESSING: DEM preparation, vector → factor rasters, cost surface
# Output: cost_rate_raw_min_per_m.tif (and all intermediates) in out_dir
# =============================================================================

rm(list = ls())

library(terra)
library(sf)

# =============================================================================
# Paths
# =============================================================================
raster_dir <- "Session10/Arda/data/rasters"
vector_dir <- "Session10/Arda/data/vectors"
out_dir    <- "Session10/Arda/data/output"
dir.create(out_dir, showWarnings = FALSE)

CRS_ARDA <- "EPSG:32631"
vec_gpkg <- file.path(vector_dir, "vectors.gpkg")

# =============================================================================
# Step 0: DEM preparation
# 10k.jpg stores elevation as byte values 0–255; *20 → realistic heights ~5100 m max
# =============================================================================
dem_jpg    <- rast(file.path(raster_dir, "10k.jpg"))
dem_scaled <- dem_jpg[[1]] * 20
crs(dem_scaled) <- CRS_ARDA
writeRaster(dem_scaled, file.path(out_dir, "arda_dem_scaled.tif"), overwrite = TRUE)
rm(dem_jpg, dem_scaled); gc()

# Reload from disk — file-backed, no lazy chain attached
template <- rast(file.path(out_dir, "arda_dem_scaled.tif"))

# Slope in degrees
slope_deg <- terrain(template, v = "slope", unit = "degrees")
writeRaster(slope_deg, file.path(out_dir, "arda_dem_scaled_slope_deg.tif"), overwrite = TRUE)
rm(slope_deg); gc()

# =============================================================================
# Read a layer from the gpkg, convert to SpatVector in the right CRS,
# optionally buffer (no union needed — rasterize handles overlapping features),
# burn a constant factor value, write directly to file.
# =============================================================================
burn_layer <- function(layer, factor_val, out_file, buf_dist = 0, background = 1) {
  v <- vect(st_transform(st_read(vec_gpkg, layer = layer, quiet = TRUE), CRS_ARDA))
  if (buf_dist > 0) v <- buffer(v, width = buf_dist)
  v$factor <- factor_val
  rasterize(v, template, field = "factor", background = background,
            filename = out_file, overwrite = TRUE)
}

# =============================================================================
# Step 1a: Vector → factor rasters
# =============================================================================
roads_factor    <- burn_layer("Roads",    0.7, file.path(out_dir, "roads_factor.tif"),    buf_dist = 200); gc()
rivers_factor   <- burn_layer("Rivers",   6.0, file.path(out_dir, "rivers_factor.tif"),   buf_dist = 200); gc()
forests_factor  <- burn_layer("forests",  1.6, file.path(out_dir, "forests_factor.tif")); gc()
wetlands_factor <- burn_layer("Wetlands", 5.0, file.path(out_dir, "wetlands_factor.tif")); gc()

# Lakes are a hard barrier — background stays NA so mask() only fires on lake cells
v_lakes <- vect(st_transform(st_make_valid(
                  st_read(vec_gpkg, layer = "lakes", quiet = TRUE)), CRS_ARDA))
v_lakes$barrier <- 1L
lakes_rast <- rasterize(v_lakes, template, field = "barrier", background = NA,
                        filename = file.path(out_dir, "lakes_barrier.tif"), overwrite = TRUE)
rm(v_lakes); gc()

# =============================================================================
# Step 1b: Slope factor reclassification
#   0–3°   → 1.0  (flat)
#   3–8°   → 1.2  (little inclined)
#   8–15°  → 1.8  (starting to get exhausting)
#   15–25° → 3.0  (steep)
#   25–35° → 6.0  (very steep)
#   >35°   → 12.0 (nearly impossible to climb)
# =============================================================================
slope_deg <- rast(file.path(out_dir, "arda_dem_scaled_slope_deg.tif"))
rcl <- matrix(c(
   0,  3,  1.0,
   3,  8,  1.2,
   8, 15,  1.8,
  15, 25,  3.0,
  25, 35,  6.0,
  35, Inf, 12.0
), ncol = 3, byrow = TRUE)
slope_factor <- classify(slope_deg, rcl, include.lowest = TRUE,
                         filename = file.path(out_dir, "slope_factor.tif"), overwrite = TRUE)
rm(slope_deg); gc()

# =============================================================================
# Step 1c: Combine into cost surface (min/m)
# Base walking speed on flat terrain: 4 km/h = 66.67 m/min → 0.015 min/m
# =============================================================================
cost_surface <- 0.015 * slope_factor * roads_factor * forests_factor *
                        wetlands_factor * rivers_factor
cost_surface <- mask(cost_surface, lakes_rast, maskvalue = 1, updatevalue = NA)
writeRaster(cost_surface, file.path(out_dir, "cost_rate_raw_min_per_m.tif"), overwrite = TRUE)

cat("Preprocessing done. Outputs in:", out_dir, "\n")
cat("  arda_dem_scaled.tif\n")
cat("  arda_dem_scaled_slope_deg.tif\n")
cat("  roads_factor.tif / rivers_factor.tif\n")
cat("  forests_factor.tif / wetlands_factor.tif\n")
cat("  lakes_barrier.tif\n")
cat("  slope_factor.tif\n")
cat("  cost_rate_raw_min_per_m.tif\n")
