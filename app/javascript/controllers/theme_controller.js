import { Controller } from "@hotwired/stimulus"

const MODES = ["light", "dark", "auto"]
const LABELS = { light: "Light", dark: "Dark", auto: "Auto" }

// Cycles <html data-theme> through light → dark → auto on click, and reflects the
// current mode as data-mode (drives the icon) + label text. "auto" falls through
// to the prefers-color-scheme media query in 01-tokens.css.
export default class extends Controller {
  static targets = ["label"]

  connect() {
    this.sync(document.documentElement.dataset.theme || "light")
  }

  cycle() {
    const current = document.documentElement.dataset.theme || "light"
    const next = MODES[(MODES.indexOf(current) + 1) % MODES.length]
    document.documentElement.dataset.theme = next
    document.cookie = `theme=${next}; path=/; max-age=31536000; samesite=lax`
    this.sync(next)
  }

  sync(mode) {
    this.element.dataset.mode = mode
    if (this.hasLabelTarget) this.labelTarget.textContent = LABELS[mode] || "Light"
  }
}
