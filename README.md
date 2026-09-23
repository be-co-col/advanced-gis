# Advanced GIS Portfolio

Coursework portfolio for **Advanced Methods in GIS and Applications**
(module MA6GIC2012, Trier University). A site-suitability workflow for
viticulture in Rhineland-Palatinate, built with open-source tools (GDAL, R,
GRASS GIS) and rendered as an interactive mkdocs site with Leaflet web maps.

## Contents

- **DEM** — terrain preparation and derivatives
- **Hydrology** — flow accumulation, streams, watershed delineation
- **Solar Radiation** — incoming radiation modeling across the terrain
- **Suitability Modeling** — combining the above into a vineyard-suitability index
- **Bonus: Least-Cost Path** — a cost-distance routing exercise

## Running locally

```bash
uv sync
uv run mkdocs serve
```

## Stack

mkdocs + [mkdocs-shadcn](https://github.com/asiffer/mkdocs-shadcn), GDAL/R/GRASS
for geoprocessing (run outside this repo — see each page's "Scripts" section
for the exact code), Leaflet for the interactive maps.
