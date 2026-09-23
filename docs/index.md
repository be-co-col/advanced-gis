---
title: Advanced GIS
summary: >
  A geospatial workflow for site-suitability modeling for viticulture in
  Rhineland-Palatinate using preferrably open-source tools
  (GDAL, R, and GRASS GIS).
external_links:
  Email Paul Deffert (Lecturer): mailto:deffert@uni-trier.de
  Email Benedikt Jochim (Author): mailto:s6bejoch@uni-trier.de
---

<style>
.badge-row{display:flex;flex-wrap:wrap;gap:.5rem;margin:.5rem 0 2rem}
.badge-row p{display:contents;margin:0}
.badge-pill{display:inline-flex;align-items:center;gap:.35rem;border-radius:calc(var(--radius) - 2px);border:1px solid var(--border);padding:.15rem .6rem;font-size:.75rem;font-weight:500;background:var(--secondary);color:var(--secondary-foreground);white-space:nowrap}
.badge-pill svg{width:14px;height:14px}
.workflow-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(230px,1fr));gap:1rem;margin:1rem 0 2rem}
.workflow-grid p{margin:0}
.workflow-card{display:flex;flex-direction:column;gap:.4rem;height:100%;border:1px solid var(--border);border-radius:var(--radius-lg);padding:1rem 1.1rem;background:var(--card);color:var(--card-foreground);text-decoration:none;transition:border-color .15s ease,box-shadow .15s ease}
.workflow-card:hover{border-color:var(--primary);box-shadow:0 1px 6px rgba(0,0,0,.08)}
.workflow-card .title{display:flex;align-items:center;gap:.5rem;font-weight:600;color:var(--card-foreground)}
.workflow-card .desc{display:block;font-size:.875rem;color:var(--muted-foreground)}
.hero-banner{position:relative;aspect-ratio:21/9;border-radius:var(--radius-lg);background-image:url('assets/img/bernd-dittrich-AtT4xMS9pvA-unsplash.jpg');background-size:cover;background-position:center;margin:.5rem 0 2rem;overflow:hidden}
.hero-credit{position:absolute;right:.6rem;bottom:.6rem;font-size:.7rem;padding:.15rem .5rem;border-radius:calc(var(--radius) - 4px);background:rgba(0,0,0,.55);color:#fff;text-decoration:none;backdrop-filter:blur(2px)}
.hero-credit:hover{background:rgba(0,0,0,.75)}
</style>

<div class="hero-banner">
<a class="hero-credit" href="https://unsplash.com/photos/an-aerial-view-of-a-vineyard-in-the-country-AtT4xMS9pvA?utm_source=unsplash&utm_medium=referral&utm_content=creditCopyText" target="_blank" rel="noreferrer">Photo by Bernd Dittrich on Unsplash</a>
</div>

<div class="badge-row" markdown="1">
<span class="badge-pill">+lucide:university+ Trier University</span>
<span class="badge-pill">+fluent:apps-list-24-regular+ Module MA6GIC2012</span>
<span class="badge-pill">+fluent:calendar-24-regular+ Deadline 30.09.2026</span>
<span class="badge-pill">+fluent:person-24-regular+ Paul Deffert &middot;
    Lecturer</span>
<span class="badge-pill">+fluent:hat-graduation-24-regular+ Benedikt Jochim &middot;
    1415876</span>
</div>

## Explore the workflow

<div class="workflow-grid" markdown="1">

<a class="workflow-card" href="introduction/" markdown="1">
<span class="title">+mdi:information-outline+ Introduction</span>
<span class="desc">Why this workflow exists, and the open-source stack behind
      it.</span>
</a>

<a class="workflow-card" href="dem/" markdown="1">
<span class="title">+mdi:image-filter-hdr+ DEM</span>
<span class="desc">Preparing and deriving terrain products from the digital
      elevation model.</span>
</a>

<a class="workflow-card" href="hydrology/" markdown="1">
<span class="title">+mdi:water-outline+ Hydrology</span>
<span class="desc">Flow accumulation, streams, and watersheds derived from the
      DEM.</span>
</a>

<a class="workflow-card" href="radiation/" markdown="1">
<span class="title">+mdi:white-balance-sunny+ Solar Radiation</span>
<span class="desc">Modeling incoming solar radiation across the terrain.</span>
</a>

<a class="workflow-card" href="suitability-model/" markdown="1">
<span class="title">+mdi:map-check-outline+ Suitability Modeling</span>
<span class="desc">Combining the individual analyses into a site-suitability
      index for vineyards.</span>
</a>

<a class="workflow-card" href="lcp/" markdown="1">
<span class="title">+mdi:map-marker-path+ Bonus: Least-Cost Path</span>
<span class="desc">An extra least-cost-path analysis to introduce other tools
      for suitability modeling.</span>
</a>

</div>
