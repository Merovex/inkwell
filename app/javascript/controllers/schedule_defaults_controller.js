import { Controller } from "@hotwired/stimulus"

// Preselects the scheduler's date/hour from an existing appointment (ISO-8601
// in the at value), converted to the browser's zone — the server renders its
// own zone's date/hour as a no-JS fallback.
export default class extends Controller {
  static targets = ["date", "hour"]
  static values = { at: String }

  connect() {
    if (!this.atValue) return

    const at = new Date(this.atValue)
    const pad = (n) => String(n).padStart(2, "0")
    const localDate = `${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())}`
    if (this.dateTarget.querySelector(`option[value="${localDate}"]`)) this.dateTarget.value = localDate
    this.hourTarget.value = at.getHours()
  }
}
