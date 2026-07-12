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
  // are translated to the US map's region codes. (jsVectorMap keeps its map
  // registry private, so the lookup table lives here.)
  regionValues() {
    if (this.mapValue === "world") return this.dataValue
    const values = {}
    for (const [ name, count ] of Object.entries(this.dataValue)) {
      const code = US_STATE_CODES[name]
      if (code) values[`US-${code}`] = count
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

const US_STATE_CODES = {
  "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
  "California": "CA", "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE",
  "District of Columbia": "DC", "Florida": "FL", "Georgia": "GA", "Hawaii": "HI",
  "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA",
  "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME",
  "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN",
  "Mississippi": "MS", "Missouri": "MO", "Montana": "MT", "Nebraska": "NE",
  "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM",
  "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH",
  "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI",
  "South Carolina": "SC", "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX",
  "Utah": "UT", "Vermont": "VT", "Virginia": "VA", "Washington": "WA",
  "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY"
}
