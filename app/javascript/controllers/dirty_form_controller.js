// Holds a form's submit button disabled until something actually changes —
// pressing Save on an untouched form is a no-op that reads as one. Wire:
//   form: data-controller="dirty-form"
//         data-action="input->dirty-form#dirty change->dirty-form#dirty"
//   button: data-dirty-form-target="submit"
// Progressive enhancement: the button starts enabled in markup (works without
// JS) and disables on connect.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]

  connect() {
    this.submitTarget.disabled = true
  }

  dirty() {
    this.submitTarget.disabled = false
  }
}
