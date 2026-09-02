import { Controller } from "@hotwired/stimulus"

// Opens/closes a native <dialog> as a modal. Put on a wrapper that holds the
// trigger(s) and the <dialog data-dialog-target="modal">. Esc-to-close is native.
// data-dialog-open-value="true" opens on connect — for dialogs that arrive via
// a turbo-frame fetch and should show themselves (e.g. the New goal modal).
export default class extends Controller {
  static targets = ["modal"]
  static values = { open: Boolean }

  connect() {
    if (this.openValue) this.modalTarget.showModal()
  }

  open() {
    this.modalTarget.showModal()
  }

  close() {
    this.modalTarget.close()
  }

  // click on the dialog element itself (the backdrop area) closes it;
  // clicks inside the panel bubble from a child, so target !== the dialog
  backdrop(event) {
    if (event.target === this.modalTarget) this.modalTarget.close()
  }
}
