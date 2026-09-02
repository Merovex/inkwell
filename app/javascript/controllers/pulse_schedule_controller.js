import { Controller } from "@hotwired/stimulus"

// The check-in schedule row. The weekday pills apply to every cadence, but
// "monthly" means a single "first <weekday> of the month", so under monthly the
// pills behave like radios (picking one clears the rest) and the help text names
// the chosen day: "Monthly asks on the first Monday."
export default class extends Controller {
  static targets = ["cadence", "hint", "days"]
  static values = { weekdaysHint: String }

  connect() {
    this.update()
  }

  get monthly() {
    return this.cadenceTarget.value === "monthly"
  }

  get dayInputs() {
    return Array.from(this.daysTarget.querySelectorAll("input[type=checkbox]"))
  }

  update() {
    if (this.monthly) this.enforceSingle()
    this.refreshHint()
  }

  // Picking a day while monthly clears the others, then re-labels the hint.
  dayToggled(event) {
    if (this.monthly && event.target.checked) this.keepOnly(event.target)
    this.refreshHint()
  }

  refreshHint() {
    if (!this.monthly) {
      this.hintTarget.textContent = this.weekdaysHintValue
      return
    }
    const chosen = this.dayInputs.find((input) => input.checked)
    const day = chosen ? chosen.dataset.dayName : "chosen weekday"
    this.hintTarget.textContent = `Monthly asks on the first ${day}.`
  }

  // Switching to monthly with several already picked keeps just the first.
  enforceSingle() {
    const checked = this.dayInputs.filter((input) => input.checked)
    if (checked.length > 1) this.keepOnly(checked[0])
  }

  keepOnly(input) {
    this.dayInputs.forEach((other) => {
      if (other !== input) other.checked = false
    })
  }
}
