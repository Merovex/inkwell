import { Controller } from "@hotwired/stimulus"

// Keeps form controls disabled while their popover is closed, so panel fields
// never ride along on ordinary submits. Controls start disabled in the markup;
// wire the popover's native toggle event: data-action="toggle->controls-disabler#sync".
export default class extends Controller {
  static targets = ["control"]

  sync(event) {
    const open = event.newState === "open"
    this.controlTargets.forEach(control => (control.disabled = !open))
  }
}
