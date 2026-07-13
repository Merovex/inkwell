import { Controller } from "@hotwired/stimulus"

// Drag-reorder a vertical list, then PATCH the new order to the server. Each
// item carries data-record-id; on drop we collect them in DOM order and post
// them under the param name (default book_record_ids[]; drops set their own via
// data-sortable-param-value). Native HTML5 drag — no library.
export default class extends Controller {
  static values = { url: String, param: { type: String, default: "book_record_ids[]" } }
  static targets = ["item"]

  start(event) {
    this.dragging = event.target.closest("[data-sortable-target='item']")
    event.dataTransfer.effectAllowed = "move"
    requestAnimationFrame(() => this.dragging?.classList.add("is-dragging"))
  }

  over(event) {
    event.preventDefault()
    const target = event.target.closest("[data-sortable-target='item']")
    if (!target || target === this.dragging) return
    const rect = target.getBoundingClientRect()
    const after = (event.clientY - rect.top) / rect.height > 0.5
    this.element.insertBefore(this.dragging, after ? target.nextSibling : target)
  }

  end() {
    this.dragging?.classList.remove("is-dragging")
    this.dragging = null
    this.save()
  }

  save() {
    const body = new URLSearchParams()
    this.itemTargets.forEach((el) => body.append(this.paramValue, el.dataset.recordId))
    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body
    })
  }
}
