import { Controller } from "@hotwired/stimulus"

// Auto-uploads a new avatar: picking a file (via the label's file input) or
// dropping one on the form submits it immediately.
export default class extends Controller {
  static targets = ["input"]

  submit() {
    if (this.inputTarget.files.length) this.element.requestSubmit()
  }

  dragover(event) {
    event.preventDefault()
    this.element.classList.add("settings__avatar-well--dragover")
  }

  dragleave() {
    this.element.classList.remove("settings__avatar-well--dragover")
  }

  drop(event) {
    event.preventDefault()
    this.element.classList.remove("settings__avatar-well--dragover")
    if (event.dataTransfer.files.length) {
      this.inputTarget.files = event.dataTransfer.files
      this.submit()
    }
  }
}
