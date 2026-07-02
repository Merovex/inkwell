import { Controller } from "@hotwired/stimulus"

// Opens/closes a native <dialog> as a modal. Put on a wrapper that holds the
// trigger(s) and the <dialog data-dialog-target="modal">. Esc-to-close is native.
export default class extends Controller {
  static targets = ["modal"]

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
