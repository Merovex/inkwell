import { Controller } from "@hotwired/stimulus"

// Copies a value (e.g. a comment's permalink, a post's public link) to the
// system clipboard. When a `flash` target is present, briefly toggles an
// `is-copied` class on the controller element so CSS can reveal a "Copied"
// overlay that fades away.
export default class extends Controller {
  static values = { text: String }
  static targets = ["flash"]

  copy() {
    const text = this.textValue

    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text).then(() => this.flash(), () => this.legacyCopy(text))
    } else {
      this.legacyCopy(text)
    }
  }

  // Fallback for non-secure contexts where the async Clipboard API is absent.
  legacyCopy(text) {
    const field = document.createElement("textarea")
    field.value = text
    field.setAttribute("readonly", "")
    field.style.position = "absolute"
    field.style.left = "-9999px"
    document.body.appendChild(field)
    field.select()
    try { document.execCommand("copy") } catch (_) { /* best effort */ }
    document.body.removeChild(field)
    this.flash()
  }

  flash() {
    if (!this.hasFlashTarget) return

    this.element.classList.add("is-copied")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.classList.remove("is-copied"), 1600)
  }
}
