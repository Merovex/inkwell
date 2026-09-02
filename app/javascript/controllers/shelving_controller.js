import { Controller } from "@hotwired/stimulus"

// The "Move to another series" picker note: as you choose a target series (or
// Standalone), spell out where the book lands. No fetch — each radio carries its
// series' title and current book count, so the landing position is count + 1.
export default class extends Controller {
  static targets = ["option", "note"]
  static values = { oldTitle: String, oldCount: Number }

  connect() { this.update() }

  update() {
    const opt = this.optionTargets.find((o) => o.checked) || this.optionTargets[0]
    if (opt) this.noteTarget.textContent = this.noteFor(opt)
  }

  noteFor(opt) {
    const title = opt.dataset.title
    const count = Number(opt.dataset.count)
    const current = opt.dataset.current === "true"
    if (current) return `Already here — pick another series to move “${this.element.dataset.bookTitle || "this book"}”.`

    const dropped = this.oldTitleValue
      ? `${this.oldTitleValue} drops to ${this.pluralBooks(this.oldCountValue - 1)} and renumbers. `
      : ""
    if (!title) return `Becomes standalone. ${dropped}Collections keep this book.`
    return `Adds to the end of ${title} — position ${count + 1}. ${dropped}Collections keep this book.`
  }

  pluralBooks(n) {
    return `${n} ${n === 1 ? "book" : "books"}`
  }
}
