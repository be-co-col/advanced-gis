---
title: Suitability Model
summary: >
  Combining terrain, hydrology, and solar radiation constraints into a
  single vineyard-suitability model.
---

Suitability here is a binary AND of independently-justified constraints,
not a weighted or fuzzy score. A cell is either suitable or it isn't, for
each of three families of reasons. This page builds the model up in stages: a
DEM-only baseline first, then two independent refinements (hydrology and solar
radiation), then the fully combined model. So each refinement's actual effect
can be seen and reported on its own, not just folded silently into a final
number.

??? example "Scripts for suitability modeling"

    === "suitability_analysis.R"

        ```R
        --8<-- "suitability_analysis.R"
        ```

    === "hydro_suitability.R"

        ```R
        --8<-- "hydro_suitability.R"
        ```

    === "solar_suitability.R"

        ```R
        --8<-- "solar_suitability.R"
        ```

    === "full_suitability.R"

        ```R
        --8<-- "full_suitability.R"
        ```

## 1. DEM-only baseline

The starting point is three terrain criteria on their own: elevation
0 - 260 m, slope 10 - 55 %, and a south-east to south-west aspect
(112.5 - 247.5 °) - the same siting logic used for the DEM/hydrology/solar
pages elsewhere on this site. All three have to hold at once for a cell
to count as suitable.

<div data-agis-report data-report-url="../assets/data/suitability/report_baseline.json"></div>

<div id="suitability-baseline-map" data-agis-webmap
  data-raster-tiles-url=""
  data-legend="none"
  data-vectors='[
    {"url":"../assets/data/suitability/baseline.geojson","color":"#89B482","fillColor":"#89B482","fillOpacity":0.6}
  ]'></div>

## 2. Hydrology / frost refinement

Cold air is denser than warm air: on clear, calm nights it drains downhill
along channels and pools in valley-bottom corridors, so radiational frost
risk is elevated there even when the surrounding slopes stay frost-free
[@poling2007]. Proximity to the stream network already extracted in
[Hydrology](hydrology.md) (thresholded at ≥5000 upstream cells) is used
here as a coarse proxy for those corridors: a 100 m buffer around every
mapped stream is excluded from the baseline, regardless of whether the
cell itself would otherwise pass the terrain criteria above.

!!! note "Limitations:"
    100 m is an example/tunable value, not one calibrated against observed
    frost damage. Narrow valleys could warrant a wider buffer and vice
    versa, and the buffer is a static spatial proxy rather than an actual
    night-time cold-air-drainage simulation.

<div data-agis-report data-report-url="../assets/data/suitability/report_hydro.json"></div>

<div id="suitability-hydro-map" data-agis-webmap
  data-raster-tiles-url=""
  data-legend="none"
  data-vectors='[
    {"url":"../assets/data/suitability/hydro-result.geojson","color":"#89B482","fillColor":"#89B482","fillOpacity":0.6},
    {"url":"../assets/data/suitability/hydro-removed.geojson","color":"#e63946","fillColor":"#e63946","fillOpacity":0.6}
  ]'></div>

Green is still suitable after the frost buffer; red is what the buffer cut.
Pan along any stream to see the corridor it carves out of the baseline.

## 3. Solar refinement

The second refinement is the relative radiation classification worked out
on the [Solar Radiation](radiation.md) page (regular-interval clustering
of growing-season global irradiation and sun duration, following
[@bois2008], see that page for the full reasoning behind why an absolute
threshold isn't used here).

<div data-agis-report data-report-url="../assets/data/suitability/report_solar.json"></div>

<div id="suitability-solar-map" data-agis-webmap
  data-raster-tiles-url=""
  data-legend="none"
  data-vectors='[
    {"url":"../assets/data/suitability/solar-result.geojson","color":"#89B482","fillColor":"#89B482","fillOpacity":0.6},
    {"url":"../assets/data/suitability/solar-removed.geojson","color":"#e63946","fillColor":"#e63946","fillOpacity":0.6}
  ]'></div>

This filter removes far less than the frost buffer (1.6 % vs. 16.7 % of the
baseline) and what it does remove is scattered rather than corridor-shaped.
Zoom in on a red patch to see it's usually a single slope catching
poorer relative radiation than its neighbours, not a systematic pattern.

## 4. Combined model

The hydrology and solar refinements are applied independently to the DEM
baseline, not one after the other, so a cell can be removed by the frost
buffer alone, the solar classification alone, or both at once. Reporting
that overlap separately (rather than just one final suitable/not-suitable
number) shows how much the two refinements are catching the same ground
versus complementary ground.

<div data-agis-report data-report-url="../assets/data/suitability/report_full.json"></div>

<div id="suitability-full-map" data-agis-webmap
  data-raster-tiles-url=""
  data-legend="none"
  data-vectors='[
    {"url":"../assets/data/suitability/full-refined.geojson","color":"#89B482","fillColor":"#89B482","fillOpacity":0.6},
    {"url":"../assets/data/suitability/full-removed.geojson","color":"#e63946","fillColor":"#e63946","fillOpacity":0.6}
  ]'></div>

Suitable area is scattered across thousands of small patches over the
whole region rather than concentrated in one place, so this map is the
better tool for exploring it than a single before/after image would be.
Pan and zoom to see exactly where the refinements bite, rather than
reading one aggregate percentage.

!!! note "Limitations:"
    The combined model inherits every limitation already noted on the DEM,
    hydrology, and solar radiation pages: clear-sky-only radiation, a
    conditioned DEM that isn't a perfect representation of reality, and a
    frost-corridor exclusion that's a coarse proxy rather than a calibrated
    model. None of these criteria are weighted by how confident we are in
    them; all count equally in the final AND.

## References

\bibliography
