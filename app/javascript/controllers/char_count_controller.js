import { Controller } from "@hotwired/stimulus"

// Live character count for a text field, flagging when it's below the SEO sweet
// spot (the max is enforced by the field's maxlength). Used on the post excerpt.
export default class extends Controller {
  static targets = ["field", "count"]
  static values = { min: Number, max: Number }

  connect() {
    this.update()
  }

  update() {
    const length = this.fieldTarget.value.length
    this.countTarget.textContent = length
    this.element.classList.toggle("char-count--short", length > 0 && length < this.minValue)
  }
}
