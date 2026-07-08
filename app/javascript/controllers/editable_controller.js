import { Controller } from "@hotwired/stimulus"

// Click-to-edit (or trigger via a menu). Swaps a display element for an input;
// Enter/blur saves, Esc cancels. If the input lives inside a form, saving
// submits it (e.g. PATCH posts#update); otherwise it's display-only.
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
    if (this.inputTarget.hidden) return // blur re-fires after Enter/Esc already closed the editor

    const value = this.inputTarget.value.trim()
    if (value) {
      this.displayTarget.textContent = value
      this.inputTarget.form?.requestSubmit()
    }
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
