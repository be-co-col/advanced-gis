/**
 * Reusable Leaflet webmap for this site: a WMS basemap (refreshed as one
 * full-extent image per settled view, like a desktop GIS's WMS canvas — see
 * refreshBasemap), an optional pre-tiled raster layer (at full native
 * resolution — see scripts/build_dem_tiles.sh / build_raster_tiles.sh),
 * optional vector overlays, a fullscreen toggle and smooth navigation.
 *
 * A raster layer's colour ramp is baked into its tiles at build time
 * (scripts/*_colors.txt) rather than picked in the browser — edit that file
 * and re-run the build script to change it. What *is* adjustable from the
 * page is the stuff that's genuinely a display preference: basemap and
 * layer opacity.
 *
 * Everything lives on `window.AGISWebmap`:
 *   AGISWebmap.init(containerId, options) -> sets up one map instance.
 *       See DEFAULTS below for every option; the interesting ones are
 *       rasterTilesUrl/rasterLabel/legend (one raster layer, optional) and
 *       vectors (any number of GeoJSON overlays, optional).
 *   AGISWebmap.addVectorLayer(map, geojson, style) -> lower-level helper
 *       for adding vector data from my own script, with per-feature
 *       symbology support. `vectors` (below) is the declarative version of
 *       this for the common case. Give an entry a `label` and it gets its
 *       own on/off checkbox (with a colour swatch) in the settings panel —
 *       `default: false` starts it unchecked. Unlabelled entries are always
 *       on.
 *
 * Pass basemap: "none" (or data-basemap="none") for pages whose data isn't
 * real-world geography (e.g. a fictional map reprojected through a real
 * CRS) — skips the WMS layer entirely instead of showing an unrelated real
 * place underneath it.
 *
 * A page doesn't have to write any JS at all: any
 * `<div data-agis-webmap data-raster-tiles-url="..." data-vectors='[...]'>`
 * gets auto-initialised once this script runs — see the bottom of this file.
 */
(function () {
  "use strict";

  // Resolve /assets/data/ relative to *this* script, so it keeps working
  // no matter how deep the current page sits in the site (mkdocs already
  // rewrites this script's own <script src> per page).
  var SCRIPT_URL = document.currentScript && document.currentScript.src;
  var DATA_BASE_URL = SCRIPT_URL
    ? new URL("../data/", SCRIPT_URL).href
    : "../data/";

  // Default legend — purely cosmetic. Keep in sync with scripts/dem_colors.txt,
  // which is the actual source of truth for the DEM tiles' colours (same
  // elevation values, same colours, in the same order).
  var DEFAULT_LEGEND = {
    title: "Elevation (m)",
    type: "continuous",
    stops: [
      { value: 20, color: "#1a4d2e" },
      { value: 150, color: "#4f9d5d" },
      { value: 300, color: "#a9c85a" },
      { value: 450, color: "#e0cf7a" },
      { value: 600, color: "#b9895a" },
      { value: 750, color: "#7a5233" },
      { value: 820, color: "#ffffff" },
    ],
    // A handful of labelled points along the bar — kept short on purpose so
    // the labels don't crowd each other. Independent of `stops` above,
    // which drives the gradient's actual colours.
    ticks: [20, 220, 420, 620, 820],
  };

  var DEFAULTS = {
    // Optional single raster tile pyramid (produced by build_dem_tiles.sh /
    // build_raster_tiles.sh). Defaults to the DEM so dem.md's plain
    // `data-agis-webmap` div (no overrides) keeps working unchanged; pass
    // rasterTilesUrl: "" (or data-raster-tiles-url="") for a vector-only map.
    rasterTilesUrl: DATA_BASE_URL + "dem-tiles/{z}/{x}/{y}.png",
    rasterMinZoom: 6,
    rasterMaxNativeZoom: 12, // native resolution of the source data (~25 m/px)
    // RLP's real extent + a little padding — keeps the tile layer from
    // firing off (and 404ing on) requests for the rest of the world while
    // panning/zooming elsewhere. All the rasters this site uses share the
    // same maximum extent (they're all derived from the same DEM grid).
    rasterBounds: [
      [48.9, 5.9],
      [51.0, 8.6],
    ],
    // Label for the opacity slider in the settings panel.
    rasterLabel: "DEM opacity",
    // Plain (untiled-pyramid) GeoTIFF for click-to-read-value popups — read
    // via windowed HTTP-range requests, never downloaded in full. Off by
    // default (unlike rasterTilesUrl, this is genuinely DEM-specific — only
    // meaningful for a continuous raster, and dem.md opts into it
    // explicitly rather than every other page needing to opt out of it).
    rasterElevationUrl: "",
    // Any number of GeoJSON overlays, loaded declaratively. Each entry:
    // { url, color, weight, fillColor, fillOpacity, opacity, dashArray,
    //   pointRadius, styleFromProperties }. styleFromProperties reads `color`/`weight`
    // straight off each feature's own properties (baked in at build time —
    // see scripts/build_hydrology_vectors.py) instead of using one flat
    // style for the whole layer.
    vectors: [],
    // One legend, describing whatever the raster layer's colours mean.
    // Pass legend: null to skip the legend control entirely.
    legend: DEFAULT_LEGEND,
    center: [49.94, 7.29],
    zoom: 8,
    minZoom: 6,
    maxZoom: 18,
    opacity: 1,
    basemap: "osm", // see BASEMAPS below
  };

  // WMS basemaps, requested once per settled view (see refreshBasemap):
  // one full-extent GetMap image per pan/zoom, the way a desktop GIS's WMS
  // canvas works, instead of a tiled grid that can show gaps if a single
  // tile fails.
  // RLP state outline, added on top of every map's own vectors (see the
  // vectors-loading chain in init) purely for geographic orientation — no
  // fill, so it never competes with whatever the page itself is showing.
  var BOUNDARY_LAYER = {
    url: DATA_BASE_URL + "boundaries/rlp-boundary.geojson",
    color: "#504945",
    weight: 2,
    fillOpacity: 0,
    opacity: 0.85,
    dashArray: "6 4",
  };

  // Sentinel key for "no basemap at all" — kept out of BASEMAPS itself since
  // it has no WMS def (baseUrl/layer) to build a GetMap request from;
  // refreshBasemap special-cases it before ever looking BASEMAPS up.
  var NONE_BASEMAP = "none";

  var BASEMAPS = {
    light_gray: {
      label: "Light gray",
      baseUrl: "https://sgx.geodatenzentrum.de/wms_topplus_open",
      layer: "web_light_grau",
      attribution:
        '&copy; <a href="https://www.bkg.bund.de">BKG</a> (TopPlusOpen), <a href="https://www.govdata.de/dl-de/zero-2-0">dl-de/by-2-0</a>',
    },
    color: {
      label: "Colour topographic",
      baseUrl: "https://sgx.geodatenzentrum.de/wms_topplus_open",
      layer: "web",
      attribution:
        '&copy; <a href="https://www.bkg.bund.de">BKG</a> (TopPlusOpen), <a href="https://www.govdata.de/dl-de/zero-2-0">dl-de/by-2-0</a>',
    },
    osm: {
      label: "OpenStreetMap",
      baseUrl: "https://ows.terrestris.de/osm/service",
      layer: "OSM-WMS",
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors, WMS: <a href="https://www.terrestris.de">terrestris</a>',
    },
  };

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  function disableMapInterference(el) {
    L.DomEvent.disableClickPropagation(el);
    L.DomEvent.disableScrollPropagation(el);
  }

  function buildWmsUrl(def, map, bounds) {
    var sw = map.options.crs.project(bounds.getSouthWest());
    var ne = map.options.crs.project(bounds.getNorthEast());
    var size = map.getSize();
    // Leaflet always sizes the ImageOverlay's <img> box to the CSS-pixel
    // footprint of `bounds`, regardless of the image's own intrinsic size.
    // Requesting exactly that size means the browser never has to scale
    // the image at all (at the cost of a bit of retina crispness).
    var width = Math.max(1, Math.round(size.x));
    var height = Math.max(1, Math.round(size.y));
    var params = {
      SERVICE: "WMS",
      VERSION: "1.3.0",
      REQUEST: "GetMap",
      LAYERS: def.layer,
      STYLES: "",
      CRS: "EPSG:3857", // projected CRS, so 1.3.0's axis-order flip doesn't apply — bbox stays x,y
      BBOX: [sw.x, sw.y, ne.x, ne.y].join(","),
      WIDTH: width,
      HEIGHT: height,
      FORMAT: "image/png",
      TRANSPARENT: "false",
    };
    return (
      def.baseUrl +
      "?" +
      Object.keys(params)
        .map(function (k) {
          return k + "=" + encodeURIComponent(params[k]);
        })
        .join("&")
    );
  }

  // ---------------------------------------------------------------------
  // Main entry point
  // ---------------------------------------------------------------------

  function init(containerOrId, options) {
    var opts = Object.assign({}, DEFAULTS, options || {});
    var wrap =
      typeof containerOrId === "string" ? document.getElementById(containerOrId) : containerOrId;
    if (!wrap) {
      console.error("AGISWebmap: container #" + containerOrId + " not found");
      return null;
    }

    wrap.classList.add("agis-map-wrap");
    var mapEl = document.createElement("div");
    mapEl.className = "agis-map";
    wrap.appendChild(mapEl);

    var map = L.map(mapEl, {
      center: opts.center,
      zoom: opts.zoom,
      minZoom: opts.minZoom,
      maxZoom: opts.maxZoom,
      zoomControl: false,
      // smooth, fractional-zoom navigation
      zoomSnap: 0,
      zoomDelta: 1,
      wheelPxPerZoomLevel: 110,
      wheelDebounceTime: 30,
      keepBuffer: 4, // pre-fetch a wider ring of raster tiles so panning doesn't reveal gaps
      inertia: true,
      fadeAnimation: true,
      worldCopyJump: false,
    });

    L.control.zoom({ position: "topleft" }).addTo(map);

    // Bottom-right so it doesn't stack on top of the legend (bottom-left).
    L.control.scale({ position: "bottomright", imperial: false }).addTo(map);

    // Dedicated pane for the WMS, z-ordered below the default tilePane
    // (where the DEM lives) — lets z-index handle the stacking order
    // instead of manually calling bringToBack() on every refresh.
    map.createPane("wmsPane");
    map.getPane("wmsPane").style.zIndex = 150; // below tilePane's default 200

    // -- basemap (WMS, refreshed once per settled view) ---------------------
    // At most one request is ever "in flight": if the view changes again
    // before the current one finishes loading, that stale request is
    // cancelled outright — otherwise a slow, superseded request can land
    // later and get revealed pinned to its own outdated bounds.
    var basemapKey = opts.basemap;
    var baseLayer = null;
    var pendingLayer = null;

    function refreshBasemap() {
      if (basemapKey === NONE_BASEMAP) {
        if (pendingLayer) {
          map.removeLayer(pendingLayer);
          pendingLayer = null;
        }
        if (baseLayer) {
          map.removeLayer(baseLayer);
          baseLayer = null;
        }
        return;
      }

      var def = BASEMAPS[basemapKey] || BASEMAPS[DEFAULTS.basemap];
      var bounds = map.getBounds();
      var url = buildWmsUrl(def, map, bounds);

      if (pendingLayer) {
        map.removeLayer(pendingLayer);
        pendingLayer = null;
      }

      var newLayer = L.imageOverlay(url, bounds, {
        opacity: 0,
        attribution: def.attribution,
        interactive: false,
        pane: "wmsPane",
      }).addTo(map);
      pendingLayer = newLayer;

      var img = newLayer.getElement();
      function reveal() {
        if (pendingLayer !== newLayer) return; // already cancelled/superseded
        // Only swap in a layer that actually finished loading — a stray
        // reveal() on a still-loading/broken image would otherwise discard
        // a perfectly good previous view for a blank one.
        if (!(img.complete && img.naturalWidth > 0)) return;
        pendingLayer = null;
        var oldLayer = baseLayer;
        baseLayer = newLayer;
        newLayer.setOpacity(1);
        if (oldLayer) map.removeLayer(oldLayer);
      }
      img.addEventListener("load", reveal, { once: true });

      var retries = 0;
      img.addEventListener("error", function () {
        retries++;
        if (retries > 3) return; // give up quietly; the previous view stays visible
        setTimeout(function () {
          img.src = url + "&retry=" + retries;
        }, 600 * retries);
      });

      setTimeout(reveal, 6000); // fallback in case a slow 'load' never fires
    }

    map.on("moveend", refreshBasemap);
    refreshBasemap();

    // Safety net for a real race: this site loads web fonts asynchronously,
    // and a font swap can reflow the page (changing the map container's
    // actual size) *after* Leaflet already measured it once at construction
    // time. Leaflet's cached size doesn't know that happened — nothing
    // re-measures it until the map itself is interacted with — so the very
    // first WMS request can end up sized for a since-stale layout, and just
    // sit there wrong until the next pan/zoom. DEM tiles don't show this
    // because GridLayer keeps re-evaluating what's visible on its own; a
    // single WMS image doesn't. Force a re-measure once the page has
    // actually finished settling; invalidateSize() fires a fresh 'moveend'
    // by itself if the size did change. window's 'load' doesn't reliably
    // wait for web fonts in every browser, so also use the Font Loading API
    // where available.
    window.addEventListener("load", function () {
      map.invalidateSize();
    });
    if (document.fonts && document.fonts.ready) {
      document.fonts.ready.then(function () {
        map.invalidateSize();
      });
    }

    // -- raster layer (optional) ---------------------------------------------
    // Capped at its own native zoom (not the map's global maxZoom): past
    // that, Leaflet would keep the layer alive by upscaling the zoom-12
    // tiles, which blurs their anti-aliased alpha edges into a translucent
    // haze over the basemap. The data has no more detail past z12 anyway,
    // so it's better to just stop showing it there than show it blurry.
    var rasterLayer = null;
    if (opts.rasterTilesUrl) {
      rasterLayer = L.tileLayer(opts.rasterTilesUrl, {
        minZoom: opts.rasterMinZoom,
        maxZoom: opts.rasterMaxNativeZoom,
        bounds: opts.rasterBounds,
        opacity: opts.opacity,
        // 404s outside the layer's cut boundary are expected (transparent
        // tiles are excluded at build time) — fail silently
        errorTileUrl:
          "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==",
      }).addTo(map);
    }

    // -- vector layers (optional) ---------------------------------------------
    // Declarative equivalent of calling AGISWebmap.addVectorLayer yourself:
    // each entry is fetched and added with a style built from its config.
    // Loaded one at a time, in array order, rather than in parallel — plain
    // vector layers share one pane with no z-index control, so whichever
    // finishes loading first would otherwise render on top regardless of
    // the order they're listed in (e.g. a watershed fill needing to stay
    // below the streams drawn over it).
    //
    // Entries with a `label` get an on/off checkbox in the settings panel
    // (see PanelControl below); vectorLayers/vectorVisible are indexed the
    // same as vectorList so a checkbox flipped before its layer has finished
    // loading is still respected once it arrives.
    var vectorList = opts.vectors || [];
    var vectorLayers = vectorList.map(function () {
      return null;
    });
    var vectorVisible = vectorList.map(function (v) {
      return v.default !== false;
    });
    var labeledVectors = vectorList.filter(function (v) {
      return v.label;
    });

    vectorList.concat([BOUNDARY_LAYER]).reduce(function (chain, v, i) {
      return chain
        .then(function () {
          return fetch(v.url).then(function (r) {
            return r.json();
          });
        })
        .then(function (geojson) {
          var layer = addVectorLayer(map, geojson, vectorStyleFromConfig(v));
          if (i < vectorList.length) {
            vectorLayers[i] = layer;
            if (!vectorVisible[i]) map.removeLayer(layer);
          }
        })
        .catch(function (err) {
          console.error("AGISWebmap: failed to load vector layer", v.url, err);
        });
    }, Promise.resolve());

    // -- click-to-read value ---------------------------------------------
    // The tiles above are just coloured pixels; exact values are read from a
    // small windowed HTTP-range request against the plain GeoTIFF instead of
    // ever downloading it whole. Only meaningful for continuous rasters.
    if (opts.rasterElevationUrl && window.GeoTIFF) {
      var elevationImage = null;
      var elevationBBox = null;
      GeoTIFF.fromUrl(opts.rasterElevationUrl)
        .then(function (tiff) {
          return tiff.getImage();
        })
        .then(function (image) {
          elevationImage = image;
          elevationBBox = image.getBoundingBox(); // [minX, minY, maxX, maxY], EPSG:3857
        })
        .catch(function (err) {
          console.error("AGISWebmap: failed to load elevation lookup", err);
        });

      map.on("click", function (e) {
        var popup = L.popup().setLatLng(e.latlng).setContent("Reading elevation…").openOn(map);

        if (!elevationImage) {
          popup.setContent("Elevation data is still loading — try again in a moment.");
          return;
        }

        var pt = map.options.crs.project(e.latlng); // EPSG:3857 metres, matches the GeoTIFF's CRS
        var width = elevationImage.getWidth();
        var height = elevationImage.getHeight();
        var col = Math.floor(((pt.x - elevationBBox[0]) / (elevationBBox[2] - elevationBBox[0])) * width);
        var row = Math.floor(((elevationBBox[3] - pt.y) / (elevationBBox[3] - elevationBBox[1])) * height);

        if (col < 0 || row < 0 || col >= width || row >= height) {
          popup.setContent("Outside the DEM extent.");
          return;
        }

        elevationImage
          .readRasters({ window: [col, row, col + 1, row + 1] })
          .then(function (result) {
            var value = result[0][0];
            popup.setContent(value === -32768 ? "No data here (outside the cut boundary)." : Math.round(value) + " m");
          })
          .catch(function (err) {
            console.error("AGISWebmap: elevation read failed", err);
            popup.setContent("Could not read elevation here.");
          });
      });
    }

    // -- fullscreen ---------------------------------------------------------
    var FullscreenControl = L.Control.extend({
      options: { position: "topleft" },
      onAdd: function () {
        var container = L.DomUtil.create("div", "leaflet-bar agis-ctl");
        var btn = L.DomUtil.create("a", "agis-btn", container);
        btn.href = "#";
        btn.title = "Toggle fullscreen";
        btn.innerHTML = ICON_EXPAND;
        L.DomEvent.on(btn, "click", function (e) {
          L.DomEvent.preventDefault(e);
          if (!document.fullscreenElement) {
            (wrap.requestFullscreen || wrap.webkitRequestFullscreen).call(wrap);
          } else {
            (document.exitFullscreen || document.webkitExitFullscreen).call(document);
          }
        });
        disableMapInterference(container);

        function onFsChange() {
          var active = document.fullscreenElement === wrap || document.webkitFullscreenElement === wrap;
          btn.innerHTML = active ? ICON_COLLAPSE : ICON_EXPAND;
          setTimeout(function () {
            map.invalidateSize();
          }, 120);
        }
        document.addEventListener("fullscreenchange", onFsChange);
        document.addEventListener("webkitfullscreenchange", onFsChange);
        // Esc exits fullscreen natively via the browser; onFsChange above
        // just keeps our icon/map size in sync when that happens.

        return container;
      },
    });
    new FullscreenControl().addTo(map);

    // -- settings panel: basemap + opacity -----------------------------------
    var PanelControl = L.Control.extend({
      options: { position: "topright" },
      onAdd: function () {
        var el = L.DomUtil.create("div", "agis-ctl agis-panel");
        el.innerHTML =
          '<div class="agis-panel-header">' +
          "<span>Map settings</span>" +
          '<span class="agis-chev">' + ICON_CHEVRON + "</span>" +
          "</div>" +
          '<div class="agis-panel-body">' +
          '<div class="agis-field"><label for="agis-basemap">Basemap</label>' +
          '<select id="agis-basemap"></select></div>' +
          (rasterLayer
            ? '<div class="agis-field"><label for="agis-opacity">' +
              opts.rasterLabel +
              '</label><input id="agis-opacity" type="range" min="0" max="1" step="0.05" /></div>'
            : "") +
          (labeledVectors.length
            ? '<div class="agis-field agis-layers"><label>Layers</label>' +
              labeledVectors
                .map(function (v) {
                  var idx = vectorList.indexOf(v);
                  return (
                    '<label class="agis-layer-toggle"><input type="checkbox" data-vector-index="' +
                    idx +
                    '"' +
                    (vectorVisible[idx] ? " checked" : "") +
                    '><i style="background:' +
                    (v.fillColor || v.color || "#3388ff") +
                    '"></i>' +
                    v.label +
                    "</label>"
                  );
                })
                .join("") +
              "</div>"
            : "") +
          '<button type="button" class="agis-reset">Reset</button>' +
          "</div>";
        disableMapInterference(el);

        var header = el.querySelector(".agis-panel-header");
        header.addEventListener("click", function () {
          el.classList.toggle("is-collapsed");
        });

        var basemapSel = el.querySelector("#agis-basemap");
        var basemapO = document.createElement("option");
        basemapO.value = NONE_BASEMAP;
        basemapO.textContent = "None";
        basemapSel.appendChild(basemapO);
        Object.keys(BASEMAPS).forEach(function (key) {
          var o = document.createElement("option");
          o.value = key;
          o.textContent = BASEMAPS[key].label;
          basemapSel.appendChild(o);
        });
        basemapSel.value = basemapKey;
        basemapSel.addEventListener("change", function () {
          basemapKey = basemapSel.value;
          refreshBasemap();
        });

        var opacityInput = el.querySelector("#agis-opacity");
        if (opacityInput) {
          opacityInput.value = opts.opacity;
          opacityInput.addEventListener("input", function () {
            rasterLayer.setOpacity(parseFloat(opacityInput.value));
          });
        }

        el.querySelectorAll(".agis-layer-toggle input").forEach(function (input) {
          input.addEventListener("change", function () {
            var idx = parseInt(input.dataset.vectorIndex, 10);
            vectorVisible[idx] = input.checked;
            var layer = vectorLayers[idx];
            if (!layer) return; // not loaded yet — vectorVisible is read once it lands
            if (input.checked) {
              if (!map.hasLayer(layer)) map.addLayer(layer);
            } else {
              if (map.hasLayer(layer)) map.removeLayer(layer);
            }
          });
        });

        el.querySelector(".agis-reset").addEventListener("click", function () {
          basemapSel.value = opts.basemap;
          basemapKey = opts.basemap;
          refreshBasemap();
          if (opacityInput) {
            opacityInput.value = opts.opacity;
            rasterLayer.setOpacity(opts.opacity);
          }
          el.querySelectorAll(".agis-layer-toggle input").forEach(function (input) {
            var idx = parseInt(input.dataset.vectorIndex, 10);
            var def = vectorList[idx].default !== false;
            input.checked = def;
            vectorVisible[idx] = def;
            var layer = vectorLayers[idx];
            if (!layer) return;
            if (def) {
              if (!map.hasLayer(layer)) map.addLayer(layer);
            } else {
              if (map.hasLayer(layer)) map.removeLayer(layer);
            }
          });
        });

        return el;
      },
    });
    new PanelControl().addTo(map);

    // -- legend ---------------------------------------------------------
    var LegendControl = L.Control.extend({
      options: { position: "bottomleft" },
      onAdd: function () {
        var legend = opts.legend;
        var el = L.DomUtil.create("div", "agis-ctl agis-legend");

        if (legend.type === "categorical") {
          var swatches = legend.classes
            .map(function (c) {
              return (
                '<span class="agis-legend-swatch"><i style="background:' +
                c.color +
                '"></i>' +
                c.label +
                "</span>"
              );
            })
            .join("");
          el.innerHTML =
            '<div class="agis-legend-title">' +
            legend.title +
            '</div><div class="agis-legend-swatches">' +
            swatches +
            "</div>";
        } else {
          var stops = legend.stops;
          var min = stops[0].value;
          var max = stops[stops.length - 1].value;
          var gradientStops = stops
            .map(function (s) {
              return s.color + " " + (((s.value - min) / (max - min)) * 100).toFixed(1) + "%";
            })
            .join(", ");
          var ticks = legend.ticks
            .map(function (t) {
              // Plain numbers position and label a tick the same way. Some
              // legends (e.g. a log-scaled one) need the label to show a
              // real-world value while the position stays on the log
              // scale — pass {value, label} for those.
              var value = typeof t === "object" ? t.value : t;
              var label = typeof t === "object" ? t.label : Math.round(t);
              var pct = ((value - min) / (max - min)) * 100;
              return (
                '<span class="agis-legend-tick" style="left:' + pct.toFixed(1) + '%">' + label + "</span>"
              );
            })
            .join("");

          el.innerHTML =
            '<div class="agis-legend-title">' +
            legend.title +
            '</div><div class="agis-legend-bar" style="background:linear-gradient(to right, ' +
            gradientStops +
            ')"></div>' +
            '<div class="agis-legend-ticks">' +
            ticks +
            "</div>";
        }

        disableMapInterference(el);
        return el;
      },
    });
    if (opts.legend) new LegendControl().addTo(map);

    return { map: map, getRasterLayer: function () { return rasterLayer; } };
  }

  var ICON_EXPAND =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H5a2 2 0 0 0-2 2v3M16 3h3a2 2 0 0 1 2 2v3M21 16v3a2 2 0 0 1-2 2h-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>';
  var ICON_COLLAPSE =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 3v3a2 2 0 0 1-2 2H4M15 3v3a2 2 0 0 0 2 2h3M4 16h3a2 2 0 0 1 2 2v3M20 16h-3a2 2 0 0 0-2 2v3"/></svg>';
  var ICON_CHEVRON =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>';

  // ---------------------------------------------------------------------
  // Extension point for later vector data (parcels, suitability results, …)
  //
  //   var layer = AGISWebmap.addVectorLayer(map, geojson, {
  //     color: "#e07a5f", weight: 2, fillOpacity: 0.35,
  //     // or supply a per-feature function for categorical/graduated symbology:
  //     style: function (feature) {
  //       return { color: feature.properties.suitability > 0.5 ? "#2a9d8f" : "#e76f51" };
  //     },
  //   });
  // ---------------------------------------------------------------------

  // Builds a style (flat object or per-feature function, whichever
  // addVectorLayer needs) from one entry of the declarative `vectors`
  // option — see DEFAULTS above and the data-vectors auto-init attribute.
  function vectorStyleFromConfig(v) {
    var base = {
      color: v.color || "#3388ff",
      weight: v.weight != null ? v.weight : 2,
      fillColor: v.fillColor || v.color || "#3388ff",
      fillOpacity: v.fillOpacity != null ? v.fillOpacity : 0.3,
      opacity: v.opacity != null ? v.opacity : 1,
      dashArray: v.dashArray || null,
    };

    var style = v.styleFromProperties
      ? function (feature) {
          return {
            color: feature.properties.color || base.color,
            weight: feature.properties.weight != null ? feature.properties.weight : base.weight,
            opacity: base.opacity,
          };
        }
      : base; // addVectorLayer accepts a flat object directly too

    if (v.pointRadius) {
      style.pointToLayer = function (feature, latlng) {
        return L.circleMarker(latlng, {
          radius: v.pointRadius,
          color: base.color,
          weight: base.weight,
          fillColor: base.fillColor,
          fillOpacity: base.fillOpacity,
        });
      };
    }
    return style;
  }

  function addVectorLayer(map, geojson, style) {
    style = style || {};
    var layer = L.geoJSON(geojson, {
      style: typeof style === "function" ? style : function () {
        return {
          color: style.color || "#3388ff",
          weight: style.weight != null ? style.weight : 2,
          fillOpacity: style.fillOpacity != null ? style.fillOpacity : 0.3,
          opacity: style.opacity != null ? style.opacity : 1,
          dashArray: style.dashArray || null,
        };
      },
      pointToLayer: style.pointToLayer,
    }).addTo(map);
    return layer;
  }

  window.AGISWebmap = { init: init, addVectorLayer: addVectorLayer };

  // ---------------------------------------------------------------------
  // Auto-init: any `<div id="..." data-agis-webmap>` gets wired up once
  // this script runs (it's loaded last, so the DOM above it is ready).
  // Optional data-* attributes override the DEFAULTS above, e.g.
  // data-opacity="0.6" data-basemap="osm" data-raster-tiles-url="".
  // data-vectors and data-legend take a JSON-encoded value (matching the
  // `vectors`/`legend` option shapes above); data-legend="none" means no
  // legend, data-raster-tiles-url="" means no raster layer.
  // ---------------------------------------------------------------------

  var DATA_ATTR_MAP = {
    rasterTilesUrl: "rasterTilesUrl",
    rasterElevationUrl: "rasterElevationUrl",
    rasterLabel: "rasterLabel",
    rasterMinZoom: "rasterMinZoom",
    rasterMaxNativeZoom: "rasterMaxNativeZoom",
    opacity: "opacity",
    basemap: "basemap",
    zoom: "zoom",
    minZoom: "minZoom",
    maxZoom: "maxZoom",
  };
  var NUMERIC_KEYS = {
    opacity: 1,
    zoom: 1,
    minZoom: 1,
    maxZoom: 1,
    rasterMinZoom: 1,
    rasterMaxNativeZoom: 1,
  };
  // JSON-encoded like data-vectors/data-legend — every other page shares the
  // same RLP extent/centre so never needed to override these, but a map of
  // genuinely different geography (e.g. the LCP bonus page) does.
  var JSON_ATTR_MAP = {
    center: "center",
    rasterBounds: "rasterBounds",
  };

  document.querySelectorAll("[data-agis-webmap]").forEach(function (el) {
    var overrides = {};
    Object.keys(DATA_ATTR_MAP).forEach(function (key) {
      var raw = el.dataset[DATA_ATTR_MAP[key]];
      if (raw === undefined) return;
      if (raw === "" && key !== "rasterTilesUrl") return; // "" only meaningful to opt out of the raster layer
      overrides[key] = NUMERIC_KEYS[key] ? parseFloat(raw) : raw;
    });
    if (el.dataset.vectors) {
      try {
        overrides.vectors = JSON.parse(el.dataset.vectors);
      } catch (err) {
        console.error("AGISWebmap: invalid data-vectors JSON", err);
      }
    }
    if (el.dataset.legend) {
      overrides.legend = el.dataset.legend === "none" ? null : JSON.parse(el.dataset.legend);
    }
    Object.keys(JSON_ATTR_MAP).forEach(function (key) {
      var raw = el.dataset[JSON_ATTR_MAP[key]];
      if (raw === undefined) return;
      try {
        overrides[key] = JSON.parse(raw);
      } catch (err) {
        console.error("AGISWebmap: invalid data-" + JSON_ATTR_MAP[key] + " JSON", err);
      }
    });
    // stashed on the element so it's reachable from devtools for debugging:
    // document.getElementById('dem-map')._agisWebmap.map
    el._agisWebmap = init(el, overrides);
  });
})();
