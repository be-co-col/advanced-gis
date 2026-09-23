---
title: Digital Elevation Model
summary: >
  Acquiring the data and preparing it for the main workflow
---
The analysis starts off with sourcing a digital elevation model **DEM** from the
[Landesamt für Vermessung und
Geobasisinformation](https://lvermgeo.rlp.de/geodaten-geoshop/open-data). This
service delivers the data as *xyz* tiles which we want to convert to a single
*tif* first. Now we can easily load it in a **GIS** to have a look at it and
only have to target a single file instead of 251 files (complete RLP
coverage) for further processing steps.

<div id="dem-map" data-agis-webmap
  data-raster-elevation-url="../assets/data/dem-elevation.tif"></div>

## Preparing the DEM

`mosaic-xyz-to-tif.sh` builds a virtual mosaic across the directory of ASCII
XYZ point-grid tiles LVermGeo delivers and writes out the single GeoTIFF used
for everything downstream. `clip-raster-via-vector.sh` then wraps `gdalwarp`
to cut that mosaic down to the study area boundary, matching the input's
data type and NoData handling automatically.

??? example "DEM preprocessing scripts"

    === "mosaic-xyz-to-tif.sh"

        ```bash
        --8<-- "mosaic-xyz-to-tif.sh"
        ```

    === "clip-raster-via-vector.sh"

        ```bash
        --8<-- "clip-raster-via-vector.sh"
        ```
