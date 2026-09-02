import { Controller } from "@hotwired/stimulus"

const CONSENT_KEY = "alcovo/excerpt_suggest/consent"
const WORKER_URL = "/excerpt_suggester_worker.js?v=2"
const MIN_SOURCE_CHARS = 200
const MAX_EXCERPT = 160
const LEAD_CHARS = 2500

// Optional, on-device excerpt suggestions: a small summarization model
// (distilbart, ~150 MB) runs in a Web Worker via transformers.js. Opt-in per
// browser — the first click shows the consent row explaining the one-time
// download; the choice is remembered in localStorage. The model itself loads
// only inside the worker, only after consent, so this eagerly-loaded
// controller stays feather-light. The suggestion just fills the form field;
// the author reviews, edits, and saves as usual.
export default class extends Controller {
  static targets = ["body", "field", "button", "status", "consent"]

  disconnect() {
    this.worker?.terminate() // free the model's memory on navigate-away
  }

  suggest() {
    if (!("Worker" in window) || !("WebAssembly" in window)) {
      return this.report("Excerpt suggestions need a newer browser.")
    }

    const text = sourceText(this.plainBody())
    if (text.length < MIN_SOURCE_CHARS) {
      return this.report("Write a bit more first — suggestions need a few paragraphs to work with.")
    }

    if (this.consented) this.run(text)
    else this.consentTarget.hidden = false
  }

  accept() {
    localStorage.setItem(CONSENT_KEY, "granted")
    this.consentTarget.hidden = true
    this.suggest()
  }

  decline() {
    this.consentTarget.hidden = true
    this.report("")
  }

  run(text) {
    this.buttonTarget.disabled = true
    this.buttonTarget.setAttribute("aria-busy", "true")
    this.report("Suggesting…")
    this.worker ??= this.#buildWorker()
    this.worker.postMessage({ text })
  }

  #buildWorker() {
    const worker = new Worker(WORKER_URL, { type: "module" })
    worker.onmessage = ({ data }) => this.#handle(data)
    worker.onerror = () => this.#fail("the model couldn't load")
    return worker
  }

  #handle(message) {
    switch (message.type) {
      case "progress":
        return this.report(`Downloading the model… ${message.percent}% (one time, ~150 MB)`)
      case "generating":
        return this.report("Suggesting… this can take a little while.")
      case "result":
        return this.#fill(trimToLimit(message.summary, MAX_EXCERPT))
      case "error":
        return this.#fail(message.message)
    }
  }

  #fill(summary) {
    this.fieldTarget.value = summary
    // char-count and the localStorage autosave both listen for input — a
    // programmatic write has to announce itself the same way typing would.
    this.fieldTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.fieldTarget.focus()
    this.#done("Suggested — review and edit as you like.")
  }

  #fail(reason) {
    this.#done(`Couldn't suggest an excerpt (${reason}). You can always write one by hand.`)
  }

  #done(message) {
    this.buttonTarget.disabled = false
    this.buttonTarget.removeAttribute("aria-busy")
    this.report(message)
  }

  report(message) {
    this.statusTarget.textContent = message
  }

  get consented() {
    try {
      return localStorage.getItem(CONSENT_KEY) === "granted"
    } catch {
      return false
    }
  }

  // Mirrors word_count_controller#plainText: Lexxy's contenteditable once
  // upgraded (innerText keeps block boundaries), the raw markup with tags
  // collapsed to spaces before then.
  plainBody() {
    const editable = this.bodyTarget.querySelector(".lexxy-editor__content")
    if (editable) return editable.innerText

    const markup = this.bodyTarget.value ?? this.bodyTarget.innerHTML ?? ""
    return markup.replace(/<[^>]*>/g, " ")
  }
}

// Pure helpers, exported for scrutiny (and unit tests, should a JS runner
// ever land).

// The model should read what the public post says: strip the email-only
// {% tipin %} splice marker, collapse whitespace, and keep the lead — meta
// descriptions want the opening, and distilbart's context is 1024 tokens
// anyway.
export function sourceText(raw) {
  return raw.replace(/\{%\s*tipin\s*%\}/g, " ").replace(/\s+/g, " ").trim().slice(0, LEAD_CHARS)
}

// Word-boundary trim to the excerpt cap, like plain_excerpt server-side —
// never end mid-word, and drop trailing punctuation before the ellipsis.
export function trimToLimit(text, max) {
  const clean = text.trim()
  if (clean.length <= max) return clean

  const cut = clean.slice(0, max - 1)
  const boundary = cut.lastIndexOf(" ")
  return (boundary > 0 ? cut.slice(0, boundary) : cut).replace(/[\s,;:.]+$/, "") + "…"
}
