import { Controller } from "@hotwired/stimulus"

// Writes a param value into a target input when triggered — e.g. "Schedule
// and save" flips the hidden scheduled_posting flag to "true" right before
// the form submits.
export default class extends Controller {
  static targets = ["input"]

  set(event) {
    this.inputTarget.value = event.params.value
  }
}
