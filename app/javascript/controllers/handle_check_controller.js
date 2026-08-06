// The Identity tab's handle typeahead: debounce keystrokes, ask
// /admin/handle_availability, and report under the field — including a
// one-click "Use <base-1234>" counter-offer when the name is taken
// (Admin::HandleAvailabilitiesController). Silent while blank; the real
// validation message still arrives on save, so this is advice, not a gate.
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "status", "suggest"]
  static values = { url: String }

  check() {
    clearTimeout(this.timer)
    const value = this.inputTarget.value.trim()
    if (!value) return this.#clear()
    this.timer = setTimeout(() => this.#ask(value), 300)
  }

  applySuggestion() {
    this.inputTarget.value = this.suggestTarget.dataset.value
    this.inputTarget.dispatchEvent(new Event("input"))
    this.inputTarget.focus()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  async #ask(value) {
    const response = await fetch(`${this.urlValue}?value=${encodeURIComponent(value)}`, {
      headers: { Accept: "application/json" }
    })
    if (!response.ok) return this.#clear()
    // A stale response must not overwrite a newer keystroke's answer.
    if (this.inputTarget.value.trim() !== value) return

    const { available, mine, taken, suggestion } = await response.json()
    if (mine) return this.#clear()

    // Problems wear the error-alert shape; good news stays a quiet hint.
    this.statusTarget.hidden = false
    this.statusTarget.className = available ? "field__hint" : "alert alert--danger"
    if (available) {
      this.statusTarget.textContent = "Available."
      this.#offer(null)
    } else if (taken) {
      this.statusTarget.textContent = "That handle is taken."
      this.#offer(suggestion)
    } else {
      this.statusTarget.textContent = "That handle can't be used."
      this.#offer(null)
    }
  }

  #offer(suggestion) {
    this.suggestTarget.hidden = !suggestion
    if (suggestion) {
      this.suggestTarget.dataset.value = suggestion
      this.suggestTarget.textContent = `Use ${suggestion}`
    }
  }

  #clear() {
    this.statusTarget.hidden = true
    this.suggestTarget.hidden = true
  }
}
