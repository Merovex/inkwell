import { Controller } from "@hotwired/stimulus"
import "jsvectormap"
import "jsvectormap-world"

// Choropleth of unique visitors by country (admin analytics). Data arrives as
// {"US": 12, "DE": 3, ...} — ISO codes from the geocoded visits. jsVectorMap
// is a UMD global (imported above for side effect).
//
// Colors come from the --geo-* custom properties on the container (set in
// analytics.css from the semantic tokens), read as computed values so the map
// matches the active light/dark theme. jsVectorMap can't take var() strings.
export default class extends Controller {
  static values = { data: Object }

  connect() {
    const styles = getComputedStyle(this.element)
    const color = (name, fallback) => styles.getPropertyValue(name).trim() || fallback

    this.map = new window.jsVectorMap({
      selector: `#${this.element.id}`,
      map: "world",
      zoomButtons: false,
      backgroundColor: "transparent",
      regionStyle: {
        initial: {
          fill: color("--geo-nodata", "#c3c8c6"),
          stroke: color("--geo-stroke", "#9aa09d"),
          strokeWidth: 0.3
        },
        hover: { fillOpacity: 0.8 }
      },
      series: {
        regions: [ {
          attribute: "fill",
          values: this.dataValue,
          scale: [ color("--geo-low", "#bfe3dc"), color("--geo-high", "#0d5c53") ],
          // Anchor the scale at zero: without it, a single-country dataset
          // has min == max and the normalization divides by zero (black fill).
          min: 0,
          max: Math.max(...Object.values(this.dataValue), 1)
        } ]
      },
      onRegionTooltipShow: (_event, tooltip, code) => {
        const count = this.dataValue[code]
        if (count) tooltip.text(`${tooltip.text()} — ${count} visitor${count === 1 ? "" : "s"}`)
      }
    })
  }

  disconnect() {
    this.map?.destroy()
    this.map = null
  }
}
