import { Controller } from "@hotwired/stimulus"

// A <details> whose contents can close it — e.g. a cancel button inside the
// disclosed panel (a summary is the only native closer, and there's one per
// details).
export default class extends Controller {
  close() {
    this.element.open = false
  }
}
