import { Controller } from "@hotwired/stimulus"

// Cycles the page background through the account tints — one step per click,
// looping. Writes data-tint onto <html> (where --site-bg resolves) and reflects
// the current tint name in an optional label.
export default class extends Controller {
  static values = { tints: Array }
  static targets = ["label"]

  connect() {
    this.sync(document.documentElement.dataset.tint)
  }

  cycle() {
    const tints = this.tintsValue
    if (tints.length === 0) return
    const root = document.documentElement
    const next = tints[(tints.indexOf(root.dataset.tint) + 1) % tints.length]
    root.dataset.tint = next
    document.cookie = `tint=${next}; path=/; max-age=31536000; samesite=lax`
    this.sync(next)
  }

  sync(tint) {
    if (this.hasLabelTarget && tint) {
      this.labelTarget.textContent = tint.charAt(0).toUpperCase() + tint.slice(1)
    }
  }
}
