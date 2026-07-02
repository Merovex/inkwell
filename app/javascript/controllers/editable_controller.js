import { Controller } from "@hotwired/stimulus"

// Click-to-edit (or trigger via a menu). Swaps a display element for an input;
// Enter/blur saves, Esc cancels. No persistence here — stub for the item view.
export default class extends Controller {
  static targets = ["display", "input"]

  edit() {
    this.inputTarget.value = this.displayTarget.textContent.trim()
    this.displayTarget.hidden = true
    this.inputTarget.hidden = false
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  save() {
    const value = this.inputTarget.value.trim()
    if (value) this.displayTarget.textContent = value
    this.done()
  }

  cancel() {
    this.done()
  }

  done() {
    this.inputTarget.hidden = true
    this.displayTarget.hidden = false
  }
}
