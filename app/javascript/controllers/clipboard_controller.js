import { Controller } from "@hotwired/stimulus"

// Copies a value (e.g. a comment's permalink) to the system clipboard.
export default class extends Controller {
  static values = { text: String }

  copy() {
    navigator.clipboard.writeText(this.textValue)
  }
}
