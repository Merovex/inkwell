import { Controller } from "@hotwired/stimulus"

// Rewrites a <time> element's text into the browser's zone and locale ("Jul 3
// at 11:00" / "Jul 3 at 11:00 AM", weekday optional); the server-rendered
// text is the no-JS fallback.
export default class extends Controller {
  static values = { datetime: String, weekday: Boolean }

  connect() {
    const at = new Date(this.datetimeValue)
    const day = at.toLocaleDateString(undefined, {
      ...(this.weekdayValue && { weekday: "short" }), month: "short", day: "numeric"
    })
    const time = at.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })
    this.element.textContent = `${day} at ${time}`
  }
}
