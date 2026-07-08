import { Controller } from "@hotwired/stimulus"

// Typeahead for series↔book membership. A debounced query hits a search
// endpoint that returns <li role="option"> results; picking one POSTs an
// Installment and the Turbo Stream response appends the chip/row. Keyboard:
// ↑/↓ move, Enter selects, Esc closes.
export default class extends Controller {
  static targets = ["input", "list"]
  static values = {
    url: String,
    postUrl: String,
    context: String,
    anchorParam: String,
    selectedParam: String,
    anchorId: String
  }

  connect() { this.active = -1 }

  search() {
    clearTimeout(this.timer)
    const q = this.inputTarget.value.trim()
    if (!q) return this.close()
    this.timer = setTimeout(() => this.fetchResults(q), 180)
  }

  async fetchResults(q) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", q)
    url.searchParams.set(this.anchorParamValue, this.anchorIdValue)
    const html = await fetch(url, { headers: { Accept: "text/html" } }).then((r) => r.text())
    this.listTarget.innerHTML = html
    this.open()
  }

  open() {
    this.listTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.active = -1
  }

  // Delayed so a mousedown on an option still fires before the list clears.
  close() {
    setTimeout(() => {
      this.listTarget.hidden = true
      this.listTarget.innerHTML = ""
      this.inputTarget.setAttribute("aria-expanded", "false")
      this.active = -1
    }, 120)
  }

  get options() {
    return [...this.listTarget.querySelectorAll("[role='option'][data-record-id]")]
  }

  select(event) {
    event.preventDefault() // keep focus on the input
    this.add(event.currentTarget.dataset.recordId)
  }

  activate(event) {
    const options = this.options
    this.active = options.indexOf(event.currentTarget)
    this.paint(options)
  }

  keydown(event) {
    const options = this.options
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.move(1, options)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.move(-1, options)
    } else if (event.key === "Enter") {
      if (this.active >= 0 && options[this.active]) {
        event.preventDefault()
        this.add(options[this.active].dataset.recordId)
      }
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  move(delta, options) {
    if (!options.length) return
    this.active = (this.active + delta + options.length) % options.length
    this.paint(options)
  }

  paint(options) {
    options.forEach((option, i) => option.classList.toggle("is-active", i === this.active))
    const current = options[this.active]
    if (current?.id) this.inputTarget.setAttribute("aria-activedescendant", current.id)
  }

  async add(selectedId) {
    const body = new URLSearchParams()
    body.set(this.anchorParamValue, this.anchorIdValue)
    body.set(this.selectedParamValue, selectedId)
    body.set("context", this.contextValue)

    const response = await fetch(this.postUrlValue, {
      method: "POST",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body
    })
    if (response.ok) window.Turbo.renderStreamMessage(await response.text())

    this.inputTarget.value = ""
    this.listTarget.hidden = true
    this.listTarget.innerHTML = ""
    this.inputTarget.focus()
  }
}
