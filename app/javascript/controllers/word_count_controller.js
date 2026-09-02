import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 200

// Live word count and reading estimate for a rich-text body, phrased exactly
// like the server's post_length helper ("1,840 words, about 8 minutes") so the
// composer, the post index and the post page all read the same. The rate comes
// in from the view (ApplicationHelper::WORDS_PER_MINUTE) — one source of truth
// for the estimate.
export default class extends Controller {
  static targets = ["source", "output"]
  static values = { wordsPerMinute: { type: Number, default: 225 } }

  connect() {
    this.render()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  // Counting reads laid-out text, so coalesce a burst of keystrokes.
  update() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.render(), DEBOUNCE_MS)
  }

  render() {
    this.timer = null

    const words = this.plainText().split(/\s+/).filter(Boolean).length
    this.outputTarget.textContent = this.phrase(words)
  }

  // An empty composer gets a bare "0 words" — a reading estimate for nothing
  // written yet is noise (the helper makes the same exception).
  phrase(words) {
    const count = `${words.toLocaleString()} ${pluralize("word", words)}`
    if (words === 0) return count

    const minutes = Math.max(1, Math.round(words / this.wordsPerMinuteValue))
    return `${count}, about ${minutes} ${pluralize("minute", minutes)}`
  }

  // Lexxy's contenteditable once it has upgraded: innerText respects block
  // boundaries — textContent would run paragraphs together and undercount.
  // Before the upgrade (an edit page can render the count before the custom
  // element mounts) read the markup instead and collapse tags to spaces, so
  // block boundaries still separate words.
  plainText() {
    const editable = this.sourceTarget.querySelector(".lexxy-editor__content")
    if (editable) return editable.innerText

    const markup = this.sourceTarget.value ?? this.sourceTarget.innerHTML ?? ""
    return markup.replace(/<[^>]*>/g, " ")
  }
}

function pluralize(word, count) {
  return count === 1 ? word : `${word}s`
}
