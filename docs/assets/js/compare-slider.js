/**
 * Before/after image comparison slider. A plain-image counterpart to
 * webmap.js's AGISWebmap — same declarative div + auto-init convention,
 * but for two static raster crops instead of a Leaflet map, since the
 * data behind them (see scripts/build_dem_compare_images.sh) is a one-off
 * illustrative render, not something worth wiring up as a full webmap.
 *
 * Usage: <div data-agis-compare
 *   data-before-url="..." data-after-url="..."
 *   data-before-label="Raw DEM" data-after-label="Conditioned DEM"></div>
 */
(function () {
  "use strict";

  function init(el) {
    var beforeUrl = el.dataset.beforeUrl;
    var afterUrl = el.dataset.afterUrl;
    if (!beforeUrl || !afterUrl) {
      console.error("AGISCompare: data-before-url/data-after-url required", el);
      return null;
    }

    el.classList.add("agis-compare-wrap");
    el.innerHTML =
      '<div class="agis-compare-stage">' +
      '<img class="agis-compare-img agis-compare-before" src="' + beforeUrl + '" alt="' + (el.dataset.beforeLabel || "Before") + '">' +
      '<div class="agis-compare-after-clip"><img class="agis-compare-img agis-compare-after" src="' + afterUrl + '" alt="' + (el.dataset.afterLabel || "After") + '"></div>' +
      '<div class="agis-compare-handle"><div class="agis-compare-knob">' + ICON_HANDLE + "</div></div>" +
      (el.dataset.beforeLabel ? '<span class="agis-compare-label agis-compare-label-before">' + el.dataset.beforeLabel + "</span>" : "") +
      (el.dataset.afterLabel ? '<span class="agis-compare-label agis-compare-label-after">' + el.dataset.afterLabel + "</span>" : "") +
      "</div>";

    var stage = el.querySelector(".agis-compare-stage");
    var clip = el.querySelector(".agis-compare-after-clip");
    var handle = el.querySelector(".agis-compare-handle");

    function setSplit(pct) {
      pct = Math.max(0, Math.min(100, pct));
      clip.style.clipPath = "inset(0 " + (100 - pct) + "% 0 0)";
      handle.style.left = pct + "%";
    }
    setSplit(50);

    var dragging = false;
    function pctFromEvent(e) {
      var rect = stage.getBoundingClientRect();
      return ((e.clientX - rect.left) / rect.width) * 100;
    }
    function onMove(e) {
      if (!dragging) return;
      setSplit(pctFromEvent(e));
    }
    handle.addEventListener("pointerdown", function (e) {
      dragging = true;
      handle.setPointerCapture(e.pointerId);
    });
    handle.addEventListener("pointermove", onMove);
    handle.addEventListener("pointerup", function () {
      dragging = false;
    });
    // Clicking/dragging anywhere on the stage also moves the handle, not
    // just the small knob itself — much easier to hit on touch devices.
    stage.addEventListener("pointerdown", function (e) {
      dragging = true;
      setSplit(pctFromEvent(e));
      stage.setPointerCapture(e.pointerId);
    });
    stage.addEventListener("pointermove", onMove);
    stage.addEventListener("pointerup", function () {
      dragging = false;
    });

    handle.tabIndex = 0;
    handle.setAttribute("role", "slider");
    handle.setAttribute("aria-valuemin", "0");
    handle.setAttribute("aria-valuemax", "100");
    handle.addEventListener("keydown", function (e) {
      var current = parseFloat(handle.style.left) || 50;
      if (e.key === "ArrowLeft") setSplit(current - 5);
      else if (e.key === "ArrowRight") setSplit(current + 5);
      else return;
      e.preventDefault();
    });

    return { setSplit: setSplit };
  }

  var ICON_HANDLE =
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 7-5 5 5 5M15 7l5 5-5 5"/></svg>';

  document.querySelectorAll("[data-agis-compare]").forEach(function (el) {
    el._agisCompare = init(el);
  });
})();
