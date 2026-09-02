import { Controller } from "@hotwired/stimulus"

// Typeahead filter for sectioned card lists (books index). Items opt in with
// data-filter-target="item" + data-filter-text; sections hide when they empty
// out and their count badges stay honest. "F" or "/" focuses the input from
// anywhere on the page; Escape clears and blurs.
export default class extends Controller {
  static targets = [ "input", "item", "section", "count", "blank" ]
  static values = { unit: { type: String, default: "item" } }

  connect() {
    this.focusHotkey = this.focusHotkey.bind(this)
    document.addEventListener("keydown", this.focusHotkey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.focusHotkey)
  }

  apply() {
    const query = this.inputTarget.value.trim().toLowerCase()

    this.itemTargets.forEach(item => {
      item.hidden = query.length > 0 && !item.dataset.filterText.includes(query)
    })

    this.sectionTargets.forEach(section => {
      const visible = this.itemTargets.filter(item => section.contains(item) && !item.hidden).length
      section.hidden = visible === 0

      const count = this.countTargets.find(badge => section.contains(badge))
      if (count) count.textContent = `${visible} ${this.unitValue}${visible === 1 ? "" : "s"}`
    })

    if (this.hasBlankTarget) this.blankTarget.hidden = this.sectionTargets.some(section => !section.hidden)
  }

  clear() {
    this.inputTarget.value = ""
    this.apply()
    this.inputTarget.blur()
  }

  // Global hotkey, ignored while the user is typing anywhere else.
  focusHotkey(event) {
    if (event.key !== "f" && event.key !== "/") return
    if (event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target.closest("input, textarea, select, [contenteditable]")) return

    event.preventDefault()
    this.inputTarget.focus()
  }
}
