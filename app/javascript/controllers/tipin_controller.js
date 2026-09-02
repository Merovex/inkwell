import { Controller } from "@hotwired/stimulus"

// Drops the {% tipin %} marker into the post body — the spot where the
// email-only tip-in splices in when the post goes out as the newsletter.
// Inserts at the editor's cursor (Lexical keeps the last selection when the
// button steals focus); the marker is plain text, so it can just as well be
// typed or moved by hand.
export default class extends Controller {
  static targets = ["body"]

  insert() {
    this.editor?.contents.insertText("{% tipin %}")
    this.editor?.focus()
  }

  // The target may be the <lexxy-editor> itself or the element the form
  // helper stamped the data attributes on — resolve to the editor either way.
  get editor() {
    const el = this.bodyTarget
    if (el.tagName === "LEXXY-EDITOR") return el
    return el.closest("lexxy-editor") || el.querySelector("lexxy-editor")
  }
}
