import { Controller } from "@hotwired/stimulus"
import "jsvectormap"
import "jsvectormap-world"

// Choropleth of unique visitors by country (admin analytics). Data arrives as
// {"US": 12, "DE": 3, ...} — ISO codes from the geocoded visits. jsVectorMap
// is a UMD global (imported above for side effect).
export default class extends Controller {
  static values = { data: Object }

  connect() {
    this.map = new window.jsVectorMap({
      selector: `#${this.element.id}`,
      map: "world",
      zoomButtons: false,
      backgroundColor: "transparent",
      regionStyle: {
        initial: { fill: "#c3c8c6" },       // no-data countries: quiet neutral
        hover: { fillOpacity: 0.8 }
      },
      series: {
        regions: [ {
          attribute: "fill",
          values: this.dataValue,
          scale: [ "#bfe3dc", "#0d5c53" ],  // syō-ro-ish teal ramp
          normalizeFunction: "polynomial"
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
