import { Controller } from "@hotwired/stimulus"

// Fills its element (a hidden input) with the browser's IANA time zone, so
// scheduled times mean the user's wall clock rather than the server's.
export default class extends Controller {
  connect() {
    this.element.value = Intl.DateTimeFormat().resolvedOptions().timeZone
  }
}
