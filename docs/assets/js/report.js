/**
 * Renders a suitability-model report JSON (see docs/assets/code-snippets/
 * suitability_analysis.R / solar_suitability.R / hydro_suitability.R /
 * full_suitability.R for the schema each script writes) as a small stat-card
 * grid. Auto-initialises any `<div data-agis-report data-report-url="...">`,
 * mirroring AGISWebmap's auto-init convention in webmap.js.
 */
(function () {
  "use strict";

  function fmtInt(n) {
    return Math.round(n).toLocaleString();
  }
  function fmtHa(n) {
    return fmtInt(n) + " ha";
  }
  function fmtPct(n) {
    return n.toFixed(1) + "%";
  }

  function stat(value, label, negative) {
    return (
      '<div class="agis-report-stat' + (negative ? " agis-report-stat-negative" : "") + '">' +
      '<span class="agis-report-value">' + value + "</span>" +
      '<span class="agis-report-label">' + label + "</span>" +
      "</div>"
    );
  }

  function renderReport(data) {
    var cards = [];

    cards.push(stat(fmtHa(data.suitable_ha), "Suitable area (" + fmtPct(data.suitable_pct) + ")"));

    if (data.removed_ha != null) {
      cards.push(
        stat(
          "−" + fmtHa(data.removed_ha),
          "Removed by refinement (−" + fmtPct(data.removed_pct) + ")",
          true
        )
      );
    }

    if (data.criteria) {
      var order = ["elevation", "slope", "aspect", "combined_and"];
      var labels = {
        elevation: "Elevation OK",
        slope: "Slope OK",
        aspect: "Aspect OK",
        combined_and: "All three combined",
      };
      order.forEach(function (key) {
        var c = data.criteria[key];
        if (!c) return;
        cards.push(stat(fmtHa(c.ha), labels[key] + " (" + fmtPct(c.pct_of_total) + ")"));
      });
    }

    if (data.refinements) {
      var r = data.refinements;
      if (r.hydro_only) {
        cards.push(
          stat("−" + fmtHa(r.hydro_only.removed_ha), "Removed by hydro only (−" + fmtPct(r.hydro_only.removed_pct) + ")", true)
        );
      }
      if (r.solar_only) {
        cards.push(
          stat("−" + fmtHa(r.solar_only.removed_ha), "Removed by solar only (−" + fmtPct(r.solar_only.removed_pct) + ")", true)
        );
      }
      if (r.both) {
        cards.push(
          stat("−" + fmtHa(r.both.removed_ha), "Removed by both (−" + fmtPct(r.both.removed_pct) + ")", true)
        );
      }
    }

    return cards.join("");
  }

  function init(el) {
    var url = el.dataset.reportUrl;
    if (!url) {
      console.error("AGISReport: data-report-url is required", el);
      return null;
    }

    el.classList.add("agis-report");
    el.innerHTML = '<div class="agis-report-loading">Loading report…</div>';

    fetch(url)
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (data) {
        var title = el.dataset.title || data.label || "Report";
        el.innerHTML =
          '<div class="agis-report-title">' +
          title +
          '</div><div class="agis-report-grid">' +
          renderReport(data) +
          "</div>";
      })
      .catch(function (err) {
        el.innerHTML = '<div class="agis-report-error">Could not load report.</div>';
        console.error("AGISReport: failed to load", url, err);
      });

    return { el: el };
  }

  document.querySelectorAll("[data-agis-report]").forEach(function (el) {
    el._agisReport = init(el);
  });

  window.AGISReport = { init: init };
})();
