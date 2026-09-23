# =============================================================================
# VECTORIZE LEAST COST PATH
# =============================================================================

rm(list = ls())

library(terra)

# =============================================================================
# Paths
# =============================================================================
out_dir <- "Session10/Arda/data/output"

CRS_ARDA <- "EPSG:32631"

lcp_file   <- file.path(out_dir, "least_cost_path.tif")
accum_file <- file.path(out_dir, "cost_distance.tif")
lcp_gpkg   <- file.path(out_dir, "least_cost_path.gpkg")

# =============================================================================
# Vectorize path raster -> ordered polyline
# Extract path cell centroids, order them source->destination by accumulated
# cost, then build a single LINESTRING through those ordered coordinates.
# =============================================================================
lcp_rast <- rast(lcp_file)
lcp_rast[lcp_rast == 0] <- NA          # background = 0 when zero_background=FALSE

path_pts     <- as.points(lcp_rast, values = FALSE, na.rm = TRUE)
cost_at_path <- extract(rast(accum_file), path_pts)[, 2]
path_pts     <- path_pts[order(cost_at_path)]

lcp_line <- vect(crds(path_pts), type = "lines", crs = CRS_ARDA)
writeVector(lcp_line, lcp_gpkg, overwrite = TRUE)

# =============================================================================
# Confirm CRS was actually embedded
# terra writes CRS into the gpkg reliably, but worth a hard check here rather
# than discovering a blank SRS later during ogr2ogr/gdalwarp reprojection.
# =============================================================================
written_crs <- crs(vect(lcp_gpkg), describe = TRUE)
if (is.na(written_crs$code) || written_crs$code != "32631") {
  stop("least_cost_path.gpkg was NOT written with EPSG:32631 - got: ",
       paste(written_crs, collapse = " / "))
}

cat("Vectorization done. Output:\n")
cat("  least_cost_path.gpkg -", nrow(crds(path_pts)), "vertices, CRS confirmed EPSG:32631\n")
