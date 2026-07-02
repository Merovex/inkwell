import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a toast after a delay; also dismisses on the close button.
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    if (this.delayValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.delayValue)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    clearTimeout(this.timer)
    this.element.classList.add("is-leaving")
    const remove = () => this.element.remove()
    this.element.addEventListener("animationend", remove, { once: true })
    setTimeout(remove, 250) // fallback when animation is disabled (reduced motion)
  }
}
