---
title: Hydrology
summary: >
  The goal in this part is to derive the watershed for a specific point
  within our study area. 
---

On this page you can see the intermediary products created to obtain the desired
product as in the watershed for a specific point. In a workflow like this where
we want to get a suitability model it may be used to reduce processing cost and
time. Especially if later on in the modeling process any solar radiation
product needs to be created which can be rather time consuming depending on the
relevant time frame and temporal resolution.

The conditioning → flow direction → flow accumulation → watershed pipeline
below follows the same general GIS framework used for spatiotemporal flood
mapping in [@abedin2019].

??? example "Script for hydrological analysis"

    === "hydro.R"

        ```R
        --8<-- "hydro.R"
        ```

## 1. Conditioned DEM

Raw DEMs almost always contain depressions ("sinks"): single cells or small
pits, mostly artifacts of the data's resolution and interpolation, that would
otherwise trap simulated flow and stop it from reaching the edge of the study
area. Before any flow routing can take place, the DEM is "conditioned" by
filling these depressions so that every cell has an unbroken downhill path out.

<div id="conditioned-dem-map" data-agis-webmap
  data-raster-tiles-url="../assets/data/conditioned-dem-tiles/{z}/{x}/{y}.png"
  data-raster-label="Conditioned DEM opacity"></div>

**Laacher See** is a good place to see this in practice: a real, deep
volcanic caldera lake, genuinely a closed basin, so filling it flattens the
whole thing out to its spill elevation. Drag the handle below to compare the
raw DEM against the conditioned one at this spot. Now the flow direction has no
dead ends.

<div data-agis-compare
  data-before-url="../assets/img/dem-compare/laacher-see-raw.jpg"
  data-after-url="../assets/img/dem-compare/laacher-see-conditioned.jpg"
  data-before-label="Raw DEM"
  data-after-label="Conditioned DEM"></div>

## 2. Flow direction

For each cell, flow direction encodes which of its 8 neighbours it drains
into (the steepest downslope neighbour) in the D8 scheme used here. This is
a categorical raster, not a continuous one: the values are direction codes,
not quantities, so they're colour-coded by class rather than on a gradient.
There are other algorithms such as the *Multiple flow directions* or *D-Inf
Algorithm* that are able to distribute one cells' water to multiple neighbours,
but standard D8 assigns all its upstream to one neighbour.

<div id="flowdir-map" data-agis-webmap
  data-raster-tiles-url="../assets/data/flowdir-tiles/{z}/{x}/{y}.png"
  data-raster-label="Flow direction opacity"
  data-legend='{"title":"Flow direction","type":"categorical","classes":[
    {"color":"#e41a1c","label":"E"},
    {"color":"#ff7f00","label":"SE"},
    {"color":"#ffff33","label":"S"},
    {"color":"#4daf4a","label":"SW"},
    {"color":"#377eb8","label":"W"},
    {"color":"#984ea3","label":"NW"},
    {"color":"#f781bf","label":"N"},
    {"color":"#a65628","label":"NE"},
    {"color":"#999999","label":"Flat"}
  ]}'></div>

## 3. Flow accumulation

Following each cell's flow direction downstream and counting how many
upstream cells drain through it provides in flow accumulation a proxy for
discharge. It's extremely right-skewed (a handful of major valleys accumulate
millions of upstream cells, while most of the landscape accumulates only a
few). Since we are not interested in the differences in accumulation on a larger
plane but want to derive the stream network the map below and its legend use a
log scale. Using a linear rendering would result in almost the entire area
being one color and thus indistinguishable.

<div id="flowacc-map" data-agis-webmap
  data-raster-tiles-url="../assets/data/flowacc-tiles/{z}/{x}/{y}.png"
  data-raster-label="Flow accumulation opacity"
  data-legend='{"title":"Flow accumulation (cells, log scale)","type":"continuous",
    "stops":[{"value":0,"color":"#f7fbff"},{"value":7.2,"color":"#08306b"}],
    "ticks":[
      {"value":0,"label":"1"},
      {"value":2,"label":"100"},
      {"value":4,"label":"10k"},
      {"value":6,"label":"1M"},
      {"value":7.11,"label":"~13M"}
    ]}'></div>

## 4. Streams and the pour point

Eliminating those cells that have less than 5000 upstream cells extracts a
stream network from what is otherwise a continuous raster surface. The lines
below are coloured and weighted by their own accumulated flow, so major rivers
stand out from small headwater streams. The marker is the pour point: the
outlet snapped onto the stream network that the watershed below was delineated
from. In this case I chose to place it at the *Peter-Altmeier-Ufer* in Koblenz
 aiming to derive the whole catchment of the German Moselle.

!!! note "Note:"
    While capturing the Moselle this way worked great as one can see, capturing
    the Rhine not so much. This is due to it following partially along the
    state boundary and traversing into the neighbouring state. Because the DEM
    covers only RLP there aren't the continuously accumulated cells
    representing its water body, but only parts of it. These circumstances lead
    to the Rhine looking more like an extension of the Moselle.

<div id="streams-map" data-agis-webmap
  data-raster-tiles-url=""
  data-legend='{"title":"Stream discharge (cells, log scale)","type":"continuous",
    "stops":[{"value":3.71,"color":"#a8d8ff"},{"value":7.11,"color":"#08306b"}],
    "ticks":[
      {"value":3.71,"label":"5k"},
      {"value":5,"label":"100k"},
      {"value":6,"label":"1M"},
      {"value":7.11,"label":"~13M"}
    ]}'
  data-vectors='[
    {"url":"../assets/data/hydrology/streams.geojson","styleFromProperties":true},
    {"url":"../assets/data/hydrology/pour-point.geojson","color":"#e63946","fillColor":"#e63946","pointRadius":8,"weight":2,"fillOpacity":0.9}
  ]'></div>

## 5. Watershed

By moving upstream from the pour-point, following the earlier computed flow
direction until we either hit a cell not draining towards the pour-point or
reaching the boundary, we get the resulting catchment area relative to that
point (or to be more precise the part of it being within the boundary). Shown
here are the catchment area and the stream network within it. Or in simple
terms: Surface water anywhere within the catchment area follows these streams
and ultimately reaches the red dot.

!!! note "Limitations:"
    Not every sink the conditioning step fills is actually an artefact (Laacher
    See above is a real one), so the conditioned DEM doesn't perfectly
    represent reality either. Springs and groundwater are also left out
    entirely, even though they're potential sources of extra water, or outlets
    besides a neighbouring cell. And as already mentioned, the DEM itself
    remains a hard limitation underlying all of this.

<div id="watershed-map" data-agis-webmap
  data-raster-tiles-url=""
  data-legend="none"
  data-vectors='[
    {"url":"../assets/data/hydrology/watershed.geojson","color":"#89B482","weight":2,"fillColor":"#89B482","fillOpacity":0.70},
    {"url":"../assets/data/hydrology/streams-watershed.geojson","styleFromProperties":true},
    {"url":"../assets/data/hydrology/pour-point.geojson","color":"#e63946","fillColor":"#e63946","pointRadius":8,"weight":2,"fillOpacity":0.9}
  ]'></div>

## References

\bibliography
