import { Controller } from "@hotwired/stimulus"
import "jsvectormap"
import "jsvectormap-world"
import "jsvectormap-us"

// Choropleth of unique visitors (admin analytics). Two shapes of data:
//   world map:    {"US": 12, "DE": 3}          — ISO country codes
//   us_aea_en map: {"North Carolina": 2, ...}  — state names, translated to
//                  the map's region codes (US-NC) via the map's own path names.
//
// Colors come from the --geo-* custom properties on the container (set in
// analytics.css from the semantic tokens). They resolve to oklch() strings,
// which jsVectorMap's color interpolator can't parse — normalizeColor() runs
// them through a canvas to get plain hex.
export default class extends Controller {
  static values = { data: Object, map: { type: String, default: "world" } }

  connect() {
    const values = this.regionValues()
    const counts = Object.values(values)

    this.map = new window.jsVectorMap({
      selector: `#${this.element.id}`,
      map: this.mapValue,
      zoomButtons: false,
      backgroundColor: "transparent",
      regionStyle: {
        initial: {
          fill: this.themeColor("--geo-nodata", "#c3c8c6"),
          stroke: this.themeColor("--geo-stroke", "#9aa09d"),
          strokeWidth: 0.3
        },
        hover: { fillOpacity: 0.8 }
      },
      series: {
        regions: [ {
          attribute: "fill",
          values,
          scale: [ this.themeColor("--geo-low", "#bfe3dc"), this.themeColor("--geo-high", "#0d5c53") ],
          // Anchor at zero: with min == max (single region) the normalization
          // divides by zero and fills come out black.
          min: 0,
          max: Math.max(...counts, 1)
        } ]
      },
      onRegionTooltipShow: (_event, tooltip, code) => {
        const count = values[code]
        if (count) tooltip.text(`${tooltip.text()} — ${count} visitor${count === 1 ? "" : "s"}`)
      }
    })
  }

  disconnect() {
    this.map?.destroy()
    this.map = null
  }

  // Data keyed for the active map: country codes pass through; state names
  // are looked up against the map definition's region names.
  regionValues() {
    if (this.mapValue === "world") return this.dataValue
    const paths = window.jsVectorMap.maps[this.mapValue].paths
    const codeByName = Object.fromEntries(
      Object.entries(paths).map(([ code, region ]) => [ region.name, code ])
    )
    const values = {}
    for (const [ name, count ] of Object.entries(this.dataValue)) {
      const code = codeByName[name]
      if (code) values[code] = count
    }
    return values
  }

  // Resolve a --geo-* token to plain hex (canvas normalizes any CSS color).
  themeColor(property, fallback) {
    const raw = getComputedStyle(this.element).getPropertyValue(property).trim()
    if (!raw) return fallback
    const context = (this.constructor._colorContext ??= document.createElement("canvas").getContext("2d"))
    context.fillStyle = fallback
    context.fillStyle = raw
    return context.fillStyle
  }
}
