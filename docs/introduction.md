---
title: Introduction
summary: >
  This website walks through suitability modeling using a case study for
  viticulture in the Moselle region in Rhineland-Palatinate (Germany). In simple
  terms: where in the region would you plant a vineyard, and why there?
  Alongside it presents an alternative workflow to the 'GIS-GUI' approach
  leveraging the power of scripting and the terminal.
---

## From ArcGIS Pro to a bash pipeline

This course is designed as an advanced GIS course built around ESRI's
[ArcGIS Pro](https://www.esri.de/de-de/arcgis/produkte/arcgis-pro/uebersicht)
and its Model Builder. Working through it that way taught me something
genuinely useful: a simple visual language for a processing pipeline, with
the ability to swap out data or tweak a step without starting over. Nice as
that is, it comes at a cost. One needs a license, and a machine with a GUI to
run it on.

Since most of these steps can be done just as well from the command line, I
took the freedom to rebuild the whole workflow using open tools instead:

- +simple-icons:gnubash+ **[bash](https://www.gnu.org/software/bash/)** general
terminal work and used to glue the pipeline together
- +simple-icons:gdal+ **[GDAL](https://www.gdal.org)** for raster/vector
  handling
- +simple-icons:r+ **[R](https://www.r-project.org)** scripts, with [`terra`](https://cran.r-project.org/web/packages/terra/index.html) for general geodata handling and via the
  [`whitebox`](https://cran.r-project.org/web/packages/whitebox/index.html) and
  [`rgrass`](https://www.cran.r-project.org/web/packages/rgrass/index.html)
    packages, driving...
      - +mdi:toolbox+ **[Whitebox](https://whiteboxgeo.com/)** for the hydrological analysis
      - +simple-icons:osgeo+ **[GRASS GIS](https://grass.osgeo.org/)** for the
        radiation analysis

No license, no GUI required, just a terminal.

## Portfolio

For the creation of this portfolio I used:

- +simple-icons:materialformkdocs+ **[MkDocs](https://www.mkdocs.org/)** with a
[community theme](https://asiffer.github.io/mkdocs-shadcn/) for the page itself
- +simple-icons:github+ **[GitHub](https://github.com/)** to host the repository
  and pages
- +simple-icons:leaflet+ **[Leaflet](https://leafletjs.com/)** to build the
webmaps
- +mdi:palette-outline+ **[Gruvbox Material](https://github.com/sainnhe/gruvbox-material)**
  colour scheme by sainnhe, applied throughout the page and the code
  highlighting

## Webmaps

Per default the webmaps use an
**[OSM](https://www.osmfoundation.org/wiki/Main_Page)** layer as basemap. Within
the Map pane in
the top right corner is a button to change this selection to either a
colored topographic or light map by **[Bundesamt für
Kartographie und Geodäsie](https://www.bkg.bund.de)** as well as again the
default OSM one. Just below that
drop down is a slider where you can change the data layers' opacity. In the top
left corner are buttons to zoom in or out (which also is possible by using
mouse or touchpad scrolling) and a full-screen toggle (which can also be exited
by `Esc`). In the lower left is a small legend and in the lower right hand
corner is a dynamic scale bar, on the very edge are the selected WMS and
Leaflet linked. All maps feature the border of Rhineland-Palatinate from
*University of California, Berkley - Global Administrative Areas Version 4.1
<https://www.gadm.org> (2025)*.

**Enjoy exploring!**

## General Info for this page

On the left you find a list of the pages (collapsible on small screens or
vertical) to skip to a certain page of your liking. In the upper right corner is
a search option that queries all of the pages and right next to it is a toggle
for light and dark themes. At the top and the bottom you can navigate back and
forth. Some code-snippets can be found in extendable sections.

## What's next

The natural next step would be to wrap all of this into a container, using
[Docker](https://www.docker.com/), [Podman](https://www.podman.io) or
[Apptainer](https://www.apptainer.org)
with the scripts rewritten to take arguments instead of hard-coded values — the
pour point for the hydrology analysis, or the parameters of the solar radiation
model, supplied by the user. That would turn this from "a workflow I ran once"
into "a tool anyone can rerun on their own study area and any suitable device
without managing dependencies."

For now, time constraints kept that effort at bay but consider it the natural
extension if this project continues.
