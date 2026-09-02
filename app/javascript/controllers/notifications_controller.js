import { Controller } from "@hotwired/stimulus"

// The bell's calm contract: opening the flyout marks everything read — the
// dot clears immediately, the server records it, and no per-item chores exist.
export default class extends Controller {
  static values = { readUrl: String }

  toggled(event) {
    if (event.newState !== "open") return

    this.element.querySelector("#notification-indicator")?.classList.remove("notifications__dot--on")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.readUrlValue, { method: "POST", headers: { "X-CSRF-Token": token } })
  }
}
