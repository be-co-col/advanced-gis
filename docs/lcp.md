---
title: Least-Cost Path
summary: >
  A bonus cost-distance exercise: routing Frodo from Hobbiton to Mt. Doom
  through a cost surface built from terrain slope and landcover, using the
  same reclassify-and-combine toolbox as the suitability model.
---

Where our [Suitability Model](suitability-model.md) asks "which cells qualify?"
, cost-distance analysis asks "what's the cheapest way to get from A to B?".
Same reclassify-and-combine toolbox, but the criteria are combined into a
single cost surface instead of a binary suitable/not-suitable mask, and a shortest
path is traced across it rather than a set of cells selected. This page walks
through building that cost surface for a fictional cost-distance exercise
(routing Frodo from Hobbiton to Mt. Doom, using the [Arda: Middle-earth
mapping project](https://github.com/bburns/Arda) as terrain/vector data) and
the least-cost path that comes out of it.

??? example "Scripts for least-cost path analysis"

    === "01_preprocessing.R"

        ```R
        --8<-- "01_preprocessing.R"
        ```

    === "02_lcp_analysis.R"

        ```R
        --8<-- "02_lcp_analysis.R"
        ```

    === "03_vectorize_lcp.R"

        ```R
        --8<-- "03_vectorize_lcp.R"
        ```

## 1. Terrain and slope

The only elevation data available for Middle-earth is a greyscale height map
(byte values 0 – 255), so it first has to be rescaled into something that
behaves like real metres:

\[
h = \text{byte} \times 20
\]

which puts the highest peaks (Caradhras, the Misty Mountains) around 5000 m.
That's plausible for real mountains, and enough relief for slope to matter.
Slope in degrees is then computed from that scaled DEM, and reclassified into a
dimensionless walking-effort factor: a flat cell costs the same as flat
ground anywhere, a 40° cell costs twelve times as much to cross.

\[
f_{\text{slope}} =
\left\{
\begin{array}{lrcll}
1.0  & 0°  & \!\text{–}\! & 3°  & \quad\text{(flat)} \\
1.2  & 3°  & \!\text{–}\! & 8°  & \quad\text{(little inclined)} \\
1.8  & 8°  & \!\text{–}\! & 15° & \quad\text{(starting to get exhausting)} \\
3.0  & 15° & \!\text{–}\! & 25° & \quad\text{(steep)} \\
6.0  & 25° & \!\text{–}\! & 35° & \quad\text{(very steep)} \\
12.0 &     & >            & 35° & \quad\text{(nearly impossible to climb)}
\end{array}
\right.
\]

This is a hand-picked step function, not a continuous one, to keep the reclass
logic identical to the suitability model's threshold-based approach. The map
below shows the result overlaid with the least-cost path derived further
down this page: watch how it bends away from the reddest cells.

<div id="lcp-slope-map" data-agis-webmap
  data-basemap="none"
  data-center='[9.0, 7.6]'
  data-zoom="5"
  data-min-zoom="4"
  data-max-zoom="12"
  data-raster-tiles-url="../assets/data/arda-slope-factor-tiles/{z}/{x}/{y}.png"
  data-raster-min-zoom="4"
  data-raster-max-native-zoom="9"
  data-raster-bounds='[[0.0, -1.75], [18.05, 17.05]]'
  data-raster-label="Slope factor opacity"
  data-legend='{"title":"Slope factor","type":"categorical","classes":[
    {"color":"#ffffb2","label":"0–3° · ×1.0 (flat)"},
    {"color":"#fed976","label":"3–8° · ×1.2 (little inclined)"},
    {"color":"#feb24c","label":"8–15° · ×1.8 (starting to get exhausting)"},
    {"color":"#fd8d3c","label":"15–25° · ×3.0 (steep)"},
    {"color":"#f03b20","label":"25–35° · ×6.0 (very steep)"},
    {"color":"#bd0026","label":"&gt;35° · ×12.0 (nearly impossible to climb)"}
  ]}'
  data-vectors='[
    {"url":"../assets/data/lcp/path.geojson","color":"#fc28a7","weight":3},
    {"url":"../assets/data/lcp/source.geojson","color":"#e9c46a","fillColor":"#e9c46a","pointRadius":6,"weight":2,"fillOpacity":0.9},
    {"url":"../assets/data/lcp/destination.geojson","color":"#d62828","fillColor":"#d62828","pointRadius":6,"weight":2,"fillOpacity":0.9}
  ]'></div>

!!! note "No real-world basemap"
    Middle-earth's data happens to be stored in EPSG:32631 (UTM 31N), a real
    coordinate system — reproject it to lat/lon and it lands over the real
    Gulf of Guinea. Showing an actual OpenStreetMap/BKG basemap underneath
    fantasy terrain would be actively misleading, so this page's maps use the
    project's own hillshade as the only backdrop instead (or nothing at all,
    for the categorical rasters here).

## 2. Building the cost surface

Landcover contributes the same way: each vector layer (roads, rivers,
forests, wetlands) is rasterized onto the DEM's grid with a constant factor
value burned in, a 200 m buffer applied to the linear features (roads,
rivers) so they don't disappear to sub-pixel width, and everywhere the
feature is absent left at a neutral factor of 1 (no effect). Lakes are
handled differently: rather than raising the cost, they're masked out
entirely (`NoData`), which the cost-distance tool treats as an outright
barrier: Frodo has no boat and can't swim with his equipment.

| Layer    | Factor    | Effect                         |
| -------- | --------- | ------------------------------ |
| Roads    | ×0.7      | faster than open ground        |
| Forests  | ×1.6      | denser vegetation slows travel |
| Wetlands | ×5.0      | boggy, exhausting ground       |
| Rivers   | ×6.0      | hard to cross                  |
| Lakes    | barrier   | impassable                     |

All of these factors, plus the slope factor above, combine multiplicatively
with a flat walking-speed baseline (4 km/h on open, flat ground = 66.67 m/min
→ 0.015 min/m) into a single cost-rate surface, in minutes needed to cross
one metre of that cell:

\[
C = 0.015 \cdot f_{\text{slope}} \cdot f_{\text{roads}} \cdot f_{\text{rivers}}
    \cdot f_{\text{forests}} \cdot f_{\text{wetlands}}
\]

with lake cells masked to `NoData` afterwards regardless of what the formula
would otherwise compute there. Every one of these factor values is a
judgement call, not a calibrated constant (see the "Limitations" note at the
bottom of this page).

## 3. Study area

Before looking at the path itself, here's the wider landscape it has to
cross: everything from Hobbiton in the northwest to Mt. Doom in the
southeast, plus the roads, rivers, lakes, forests, wetlands, mountain ridges
and major settlements from the wider Arda vector dataset (not all of which
feed into the cost model — cities and mountain ridgelines are shown purely
for orientation). Toggle layers on and off in the settings panel (top right)
to explore the terrain the cost surface above was built from.

<div id="lcp-overview-map" data-agis-webmap
  data-basemap="none"
  data-center='[9.0, 7.6]'
  data-zoom="5"
  data-min-zoom="4"
  data-max-zoom="12"
  data-raster-tiles-url="../assets/data/arda-terrain-tiles/{z}/{x}/{y}.png"
  data-raster-min-zoom="4"
  data-raster-max-native-zoom="9"
  data-raster-bounds='[[0.0, -1.75], [18.05, 17.05]]'
  data-raster-label="Hillshade opacity"
  data-legend="none"
  data-vectors='[
    {"url":"../assets/data/lcp/roads.geojson","label":"Roads","color":"#a67c52","weight":1.5},
    {"url":"../assets/data/lcp/rivers.geojson","label":"Rivers","color":"#3a86c8","weight":1.5},
    {"url":"../assets/data/lcp/lakes.geojson","label":"Lakes","color":"#1c4e80","fillColor":"#1c4e80","fillOpacity":0.6,"weight":1},
    {"url":"../assets/data/lcp/forests.geojson","label":"Forests","color":"#2f5233","fillColor":"#2f5233","fillOpacity":0.45,"weight":1,"default":false},
    {"url":"../assets/data/lcp/wetlands.geojson","label":"Wetlands","color":"#8a9a5b","fillColor":"#8a9a5b","fillOpacity":0.45,"weight":1,"default":false},
    {"url":"../assets/data/lcp/mountains.geojson","label":"Mountain ridges","color":"#6b6b6b","weight":1.5,"default":false},
    {"url":"../assets/data/lcp/cities.geojson","label":"Cities","color":"#e07a5f","fillColor":"#e07a5f","pointRadius":4,"weight":1,"fillOpacity":0.9,"default":false},
    {"url":"../assets/data/lcp/source.geojson","color":"#e9c46a","fillColor":"#e9c46a","pointRadius":7,"weight":2,"fillOpacity":0.9},
    {"url":"../assets/data/lcp/destination.geojson","color":"#d62828","fillColor":"#d62828","pointRadius":7,"weight":2,"fillOpacity":0.9}
  ]'></div>

## 4. Cost distance and the least-cost path

With a cost surface in hand, `wbt_cost_distance()` finds, for every cell,
the cheapest accumulated cost to reach it from Hobbiton, mirroring ArcGIS's
Cost Distance tool. Conceptually it's a Dijkstra relaxation over the 8
neighbours of each cell:

\[
CD(c) = \min_{n \in N(c)} \left( CD(n) + d_{n,c} \cdot \frac{C(n) + C(c)}{2} \right)
\]

where \(N(c)\) are \(c\)'s eight neighbours, \(d_{n,c}\) is 1 for an
orthogonal neighbour and \(\sqrt{2}\) for a diagonal one (a diagonal step
covers more ground), and \(C(x)\) is the cost-rate surface from above. Each
step also writes a **backlink**: which of the 8 neighbours a cell should walk
back through to retrace the cheapest route to the source. Tracing that
backlink chain from Mt. Doom back to Hobbiton using `wbt_cost_pathway()`,
mirroring ArcGIS's Cost Path / "Optimal Path as Raster" produces the
least-cost path itself, which `03_vectorize_lcp.R` turns into the single line
shown below.

<div id="lcp-result-map" data-agis-webmap
  data-basemap="none"
  data-center='[9.0, 7.6]'
  data-zoom="5"
  data-min-zoom="4"
  data-max-zoom="12"
  data-raster-tiles-url="../assets/data/arda-terrain-tiles/{z}/{x}/{y}.png"
  data-raster-min-zoom="4"
  data-raster-max-native-zoom="9"
  data-raster-bounds='[[0.0, -1.75], [18.05, 17.05]]'
  data-raster-label="Hillshade opacity"
  data-legend='{"title":"Cost model & result","type":"categorical","classes":[
    {"color":"#a67c52","label":"Roads · ×0.7 (easier)"},
    {"color":"#3a86c8","label":"Rivers · ×6.0 (hard to cross)"},
    {"color":"#2f5233","label":"Forests · ×1.6 (slower)"},
    {"color":"#8a9a5b","label":"Wetlands · ×5.0 (boggy)"},
    {"color":"#1c4e80","label":"Lakes · barrier"},
    {"color":"#fc28a7","label":"Least-cost path"},
    {"color":"#e9c46a","label":"Hobbiton (start)"},
    {"color":"#d62828","label":"Mt. Doom (destination)"}
  ]}'
  data-vectors='[
    {"url":"../assets/data/lcp/roads.geojson","label":"Roads","color":"#a67c52","weight":1.5,"default":false},
    {"url":"../assets/data/lcp/rivers.geojson","label":"Rivers","color":"#3a86c8","weight":1.5,"default":false},
    {"url":"../assets/data/lcp/forests.geojson","label":"Forests","color":"#2f5233","fillColor":"#2f5233","fillOpacity":0.45,"weight":1,"default":false},
    {"url":"../assets/data/lcp/wetlands.geojson","label":"Wetlands","color":"#8a9a5b","fillColor":"#8a9a5b","fillOpacity":0.45,"weight":1,"default":false},
    {"url":"../assets/data/lcp/lakes.geojson","label":"Lakes","color":"#1c4e80","fillColor":"#1c4e80","fillOpacity":0.6,"weight":1,"default":false},
    {"url":"../assets/data/lcp/path.geojson","color":"#fc28a7","weight":3},
    {"url":"../assets/data/lcp/source.geojson","color":"#e9c46a","fillColor":"#e9c46a","pointRadius":7,"weight":2,"fillOpacity":0.9},
    {"url":"../assets/data/lcp/destination.geojson","color":"#d62828","fillColor":"#d62828","pointRadius":7,"weight":2,"fillOpacity":0.9}
  ]'></div>

Toggle the factor layers back on to see which of them the path is actually
routing around. It leans on roads where they happen to run the right
direction, skirts wetlands and rivers rather than crossing them head-on, and
avoids the steep slope classes from the map in section 1 wherever a flatter
detour is available.

!!! note "Limitations"
    Every factor value on this page (roads ×0.7, rivers ×6.0, the whole
    slope step function, …) is a plausibility judgement, not a calibrated
    number meaning there's no field data to fit them against, unlike a real
    hiking-cost model (e.g. Tobler's hiking function). The combination is a
    plain product of independent factors, which has no particular
    theoretical grounding beyond "each of these things independently makes
    travel harder or easier." The 200 m/pixel DEM is also coarse enough that
    small terrain features (a single ridge, a narrow pass) simply aren't
    resolved. And this is only one path among many reasonable ones. Going
    forward with this project one could explore a "stealthy" route with
    different factor values (avoiding roads rather than favouring them),
    per-region danger factors (Mirkwood, Moria, Mordor itself), and
    isochrones derived from the same accumulated-cost raster. For now I'll be
    leaving it as what it is since it serves its purpose to showcase another
    category of suitability-modeling and ends this thematic exploration in a fun
    way.
