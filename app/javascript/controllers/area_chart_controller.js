import { Controller } from "@hotwired/stimulus"

// Draws a small overlapping-area chart (the broadcast overview) from a JSON
// data value — client-rendered so the server ships data, not markup, and the
// fills stay theme-aware through CSS (chart.css). Deliberately not a chart
// library: one shape, ~fifty lines; revisit if charts multiply.
//
//   <div class="chart" data-controller="area-chart"
//        data-area-chart-data-value='{"labels":[…],"series":[{"name","key","values":[…]}]}'>
//
// Each series becomes <polygon class="chart__area chart__area--<key>"> plus a
// legend key. The SVG is aria-hidden — the totals sentence beside the chart
// carries the numbers for assistive tech.
export default class extends Controller {
  static values = { data: Object }

  static W = 720
  static H = 160

  connect() {
    const { labels, series } = this.dataValue
    const max = Math.max(1, ...series.flatMap(s => s.values))
    const { W, H } = this.constructor

    const points = values => values.map((v, i) =>
      `${(i * (W / Math.max(1, values.length - 1))).toFixed(1)},${(H - (v / max) * H).toFixed(1)}`
    ).join(" ")

    this.element.innerHTML = `
      <svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" class="chart__svg" aria-hidden="true">
        ${series.map(s => `<polygon class="chart__area chart__area--${s.key}" points="0,${H} ${points(s.values)} ${W},${H}"/>`).join("")}
      </svg>
      <div class="chart__axis" aria-hidden="true">
        <span>${labels[0] ?? ""}</span><span>${labels.at(-1) ?? ""}</span>
      </div>
      <div class="chart__legend">
        ${series.map(s => `<span class="chart__key chart__key--${s.key}">${s.name}</span>`).join("")}
      </div>`
  }
}
