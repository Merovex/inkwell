import { Controller } from "@hotwired/stimulus"

// Typeahead over the vendored Google Fonts list (an asset; fetched once and
// shared). Picking a family loads its face so the input previews it, then
// dispatches font-picker:change {slot, family} for the designer to commit.
// Keyboard: ↑/↓ move, Enter selects, Esc closes.
let FAMILIES = null

export default class extends Controller {
  static targets = ["input", "list"]
  static values = { url: String, slot: String }

  connect() {
    this.active = -1
  }

  async search() {
    const q = this.inputTarget.value.trim().toLowerCase()
    if (q.length < 2) return this.hideList()

    if (!FAMILIES) FAMILIES = await fetch(this.urlValue).then(response => response.json())
    const matches = FAMILIES.filter(f => f.name.toLowerCase().includes(q)).slice(0, 20)

    this.listTarget.replaceChildren(...matches.map(f => {
      const option = document.createElement("li")
      option.role = "option"
      option.textContent = f.name
      option.dataset.family = f.name
      // mousedown so selection beats the input's blur
      option.addEventListener("mousedown", event => { event.preventDefault(); this.select(f.name) })
      return option
    }))
    this.listTarget.hidden = matches.length === 0
    this.active = -1
  }

  navigate(event) {
    const options = [...this.listTarget.children]
    if (this.listTarget.hidden || options.length === 0) return

    switch (event.key) {
      case "ArrowDown": event.preventDefault(); this.highlight(options, this.active + 1); break
      case "ArrowUp": event.preventDefault(); this.highlight(options, this.active - 1); break
      case "Enter": event.preventDefault(); this.select((options[this.active] || options[0]).dataset.family); break
      case "Escape": this.hideList(); break
    }
  }

  close() {
    // Delayed so a mousedown on an option still lands first.
    setTimeout(() => this.hideList(), 120)
  }

  select(family) {
    this.inputTarget.value = family
    this.previewFace(family)
    this.hideList()
    this.dispatch("change", { detail: { slot: this.slotValue, family } })
  }

  // Called by the designer when it clears or restores custom fonts.
  display(family) {
    this.inputTarget.value = family || ""
    this.inputTarget.style.fontFamily = family ? `'${family}'` : ""
    if (family) this.previewFace(family)
  }

  // --- internals

  highlight(options, index) {
    this.active = Math.max(0, Math.min(index, options.length - 1))
    options.forEach((option, i) => option.setAttribute("aria-selected", i === this.active))
    options[this.active].scrollIntoView({ block: "nearest" })
  }

  hideList() {
    this.listTarget.hidden = true
    this.listTarget.replaceChildren()
    this.active = -1
  }

  previewFace(family) {
    const id = `gf-preview-${family.replaceAll(" ", "-")}`
    if (!document.getElementById(id)) {
      const link = Object.assign(document.createElement("link"), {
        id, rel: "stylesheet",
        href: `https://fonts.googleapis.com/css2?family=${family.replaceAll(" ", "+")}&display=swap`
      })
      document.head.append(link)
    }
    this.inputTarget.style.fontFamily = `'${family}'`
  }
}
