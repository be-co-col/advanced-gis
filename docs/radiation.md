---
title: Solar Radiation
summary: >
  On this page we are taking a look at exemplary ways to model solar radiation
  based on a DEM.
---

!!! note "Limitations:"
    All of this modeling is based on clear skies. So modeled radiation values are
    not to be viewed as an actual prediction under real world circumstances.
    Instead of applying thresholds that would apply to the real world one could
    use them to find out which areas have more potential than others relatively,
    following the same regular-interval classification approach used for
    Bordeaux's winegrowing region [@bois2008].

??? example "Script to model solar radiation"
  
    === "solar_rgrass.R"

        ```R
        --8<-- "solar_rgrass.R"
        ```

These four rasters come from GRASS `r.sun` (via `rgrass`), modelling
clear-sky solar irradiation across the growing season. Every 5th day from April
1 to October 31, 2025, summed and scaled up to approximate the full season.
`r.sun` accounts for the terrain's slope and aspect, so south-facing slopes and
ridge tops read markedly higher than shaded valleys and north-facing ground,
using the same DEM-derived hemispherical-viewshed approach to complex
topography validated in [@tovarpescador2006].

All four colour ramps are stretched between each raster's 2nd and 98th
percentile rather than its true min/max: a handful of extreme outlier cells
(deep, near-permanently shaded pockets) span a far wider range than the rest
of the landscape, and a ramp honouring the true extremes would have made
almost the entire map read as a single colour. Values outside that band
simply clip to the nearest end colour.

## Global irradiation

Global irradiation is the total energy received per unit area as in direct beam
plus diffuse sky radiation combined, and is the headline figure for anything
energy or growth-related, from solar panel siting to vineyard suitability.
Modelled radiation is directly tied to vineyard quality and value in
cool-climate regions such as the nearby Moselle valley [@ashenfelter2010].

<div id="radiation-global-map" data-agis-webmap
  data-raster-tiles-url="../assets/data/radiation-global-tiles/{z}/{x}/{y}.png"
  data-raster-label="Global irradiation opacity"
  data-legend='{"title":"Global irradiation (Wh/m², Apr–Oct)","type":"continuous",
    "stops":[
      {"value":1119569.34,"color":"#ffffb2"},
      {"value":1250246.01,"color":"#fecc5c"},
      {"value":1380922.67,"color":"#fd8d3c"},
      {"value":1511599.34,"color":"#f03b20"},
      {"value":1642276.00,"color":"#bd0026"}
    ],
    "ticks":[
      {"value":1119569.34,"label":"1.1M"},
      {"value":1250246.01,"label":"1.25M"},
      {"value":1380922.67,"label":"1.4M"},
      {"value":1511599.34,"label":"1.5M"},
      {"value":1642276.00,"label":"1.6M"}
    ]}'></div>

## Direct irradiation

Direct beam irradiation ,or sunlight reaching a cell in an unobstructed
straight line from the sun, is what actually gets blocked by terrain
shading. It has the widest relative spread of the three irradiation layers,
since it (unlike diffuse) drops sharply wherever a slope is self-shaded or
shadowed by surrounding terrain for much of the day.

<div id="radiation-direct-map" data-agis-webmap
  data-raster-tiles-url="../assets/data/radiation-direct-tiles/{z}/{x}/{y}.png"
  data-raster-label="Direct irradiation opacity"
  data-legend='{"title":"Direct irradiation (Wh/m², Apr–Oct)","type":"continuous",
    "stops":[
      {"value":898301.22,"color":"#ffffb2"},
      {"value":1017095.54,"color":"#fecc5c"},
      {"value":1135889.86,"color":"#fd8d3c"},
      {"value":1254684.17,"color":"#f03b20"},
      {"value":1373478.49,"color":"#bd0026"}
    ],
    "ticks":[
      {"value":898301.22,"label":"900k"},
      {"value":1017095.54,"label":"1.0M"},
      {"value":1135889.86,"label":"1.14M"},
      {"value":1254684.17,"label":"1.25M"},
      {"value":1373478.49,"label":"1.37M"}
    ]}'></div>

## Diffuse irradiation

Diffuse irradiation is sunlight scattered by the atmosphere and sky rather
than arriving directly. It still reaches shaded terrain, just weaker, which
is why it varies far less across the landscape than direct beam does. This
map uses the same colour ramp as the other two, but note the legend's narrower
range. In general the same pattern can be observed as with the global
irradiation as in north-facing slopes representing the lower end of the scale
and the south-facing ones the higher one.

<div id="radiation-diffuse-map" data-agis-webmap
  data-raster-tiles-url="../assets/data/radiation-diffuse-tiles/{z}/{x}/{y}.png"
  data-raster-label="Diffuse irradiation opacity"
  data-legend='{"title":"Diffuse irradiation (Wh/m², Apr–Oct)","type":"continuous",
    "stops":[
      {"value":208492.34,"color":"#ffffb2"},
      {"value":221202.91,"color":"#fecc5c"},
      {"value":233913.48,"color":"#fd8d3c"},
      {"value":246624.05,"color":"#f03b20"},
      {"value":259334.63,"color":"#bd0026"}
    ],
    "ticks":[
      {"value":208492.34,"label":"210k"},
      {"value":221202.91,"label":"220k"},
      {"value":233913.48,"label":"235k"},
      {"value":246624.05,"label":"245k"},
      {"value":259334.63,"label":"260k"}
    ]}'></div>

## Sunshine duration

Sunshine duration is a headcount, not an energy total: the number of hours a
cell receives direct sun over the season, regardless of intensity. It tracks
direct irradiation closely, since both are driven by the same terrain
shading, but is easier to reason about in everyday terms. The actual spread
would be smaller if we were able to account for clouds here.

!!! note "Note:"
    To conclude this section it can be said that the value of the radiation
    products lies within determining which areas are definitely not meeting the
    requirements rather than finding those who do meet them.

<div id="radiation-duration-map" data-agis-webmap
  data-raster-tiles-url="../assets/data/radiation-duration-tiles/{z}/{x}/{y}.png"
  data-raster-label="Sunshine duration opacity"
  data-legend='{"title":"Sunshine duration (hours, Apr–Oct)","type":"continuous",
    "stops":[
      {"value":2167.5,"color":"#ffffb2"},
      {"value":2374.4,"color":"#fecc5c"},
      {"value":2581.3,"color":"#fd8d3c"},
      {"value":2788.1,"color":"#f03b20"},
      {"value":2995.0,"color":"#bd0026"}
    ],
    "ticks":[
      {"value":2167.5,"label":"2170"},
      {"value":2374.4,"label":"2375"},
      {"value":2581.3,"label":"2580"},
      {"value":2788.1,"label":"2790"},
      {"value":2995.0,"label":"2995"}
    ]}'></div>

## References

\bibliography
