import { Controller } from "@hotwired/stimulus"

// Auto-uploads an image: picking a file (via the label's file input) or
// dropping one on the form submits it immediately. Reused for avatars and book
// covers; the dragover highlight class is supplied per use via the classes API.
export default class extends Controller {
  static targets = ["input"]
  static classes = ["dragover"]

  submit() {
    if (this.inputTarget.files.length) this.element.requestSubmit()
  }

  dragover(event) {
    event.preventDefault()
    if (this.hasDragoverClass) this.element.classList.add(this.dragoverClass)
  }

  dragleave() {
    if (this.hasDragoverClass) this.element.classList.remove(this.dragoverClass)
  }

  drop(event) {
    event.preventDefault()
    if (this.hasDragoverClass) this.element.classList.remove(this.dragoverClass)
    if (event.dataTransfer.files.length) {
      this.inputTarget.files = event.dataTransfer.files
      this.submit()
    }
  }
}
