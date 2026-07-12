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
    // jsVectorMap's series is categorical — scale[value] is a straight lookup,
    // no numeric interpolation. So: quantize counts into STEPS buckets and
    // hand it a bucket→color ramp we interpolate ourselves.
    const STEPS = 5
    const counts = this.regionValues()
    const max = Math.max(...Object.values(counts), 1)
    const low = this.themeColor("--geo-low", "#bfe3dc")
    const high = this.themeColor("--geo-high", "#0d5c53")

    const scale = {}
    for (let step = 1; step <= STEPS; step++) {
      scale[step] = this.mixHex(low, high, STEPS === 1 ? 1 : (step - 1) / (STEPS - 1))
    }
    const buckets = {}
    for (const [ code, count ] of Object.entries(counts)) {
      buckets[code] = Math.max(1, Math.ceil((count / max) * STEPS))
    }

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
      series: { regions: [ { attribute: "fill", values: buckets, scale } ] },
      onRegionTooltipShow: (_event, tooltip, code) => {
        const count = counts[code]
        if (count) tooltip.text(`${tooltip.text()} — ${count} visitor${count === 1 ? "" : "s"}`)
      }
    })
  }

  // Linear blend of two #rrggbb colors, t in 0..1.
  mixHex(from, to, t) {
    const parse = (hex) => [ 1, 3, 5 ].map((i) => parseInt(hex.slice(i, i + 2), 16))
    const [ r1, g1, b1 ] = parse(from)
    const [ r2, g2, b2 ] = parse(to)
    return "#" + [ r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t ]
      .map((channel) => Math.round(channel).toString(16).padStart(2, "0")).join("")
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

  // Resolve a --geo-* token to plain #rrggbb by painting a pixel and reading
  // it back — the only reliable way to normalize oklch()/color-mix() values
  // (the fillStyle getter isn't guaranteed to serialize them as hex).
  themeColor(property, fallback) {
    const raw = getComputedStyle(this.element).getPropertyValue(property).trim()
    if (!raw) return fallback
    if (!this.constructor._colorContext) {
      const canvas = document.createElement("canvas")
      canvas.width = canvas.height = 1
      this.constructor._colorContext = canvas.getContext("2d", { willReadFrequently: true })
    }
    const context = this.constructor._colorContext
    context.fillStyle = fallback
    context.fillStyle = raw
    context.fillRect(0, 0, 1, 1)
    const [ r, g, b ] = context.getImageData(0, 0, 1, 1).data
    return "#" + [ r, g, b ].map((channel) => channel.toString(16).padStart(2, "0")).join("")
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
