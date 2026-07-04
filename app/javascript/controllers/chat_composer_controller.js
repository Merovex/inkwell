import { Controller } from "@hotwired/stimulus"

// Chat-style keyboard for a composer textarea: Enter sends, Ctrl+Enter drops
// to a new line — the opposite of a bare textarea. Shift+Enter keeps its
// native newline behavior.
export default class extends Controller {
  send(event) {
    if (event.ctrlKey) {
      event.preventDefault()
      event.target.setRangeText("\n", event.target.selectionStart, event.target.selectionEnd, "end")
    } else if (!event.shiftKey) {
      event.preventDefault()
      event.target.form.requestSubmit()
    }
  }
}
