// Suggest-excerpt model worker. Lives in public/ because import maps don't
// reach workers — the pinned CDN URL below is the one loading mechanism that
// works here, and the runtime .wasm and model weights come from CDNs
// regardless (see ADR 0028). The model downloads once from huggingface.co
// into the browser's Cache API; nothing leaves the machine. public/ is served
// undigested, so bump the ?v= query on WORKER_URL in
// excerpt_suggest_controller.js whenever this file changes.
// Pinned to the 3.x line: transformers.js 4.x bundles an onnxruntime-web
// whose QDQ→MatMulNBits graph transform rejects this model's older quantized
// export ("Missing required scale … DequantizeLinear"). Verified in-browser:
// 4.2.0 fails to create a session, 3.8.1 loads and generates. Re-test before
// any bump to 4.x.
const TRANSFORMERS_URL = "https://cdn.jsdelivr.net/npm/@huggingface/transformers@3.8.1"
const MODEL = "Xenova/distilbart-cnn-6-6"

let summarizerPromise

function summarizer(onProgress) {
  summarizerPromise ??= import(TRANSFORMERS_URL).then(({ pipeline }) =>
    pipeline("summarization", MODEL, { dtype: "q8", progress_callback: onProgress }))
  return summarizerPromise
}

self.onmessage = async ({ data }) => {
  try {
    // The download arrives as several files, each reporting its own
    // percentage — fold them into one number for the status line.
    const files = new Map()
    const pipe = await summarizer((progress) => {
      if (progress.status !== "progress" || !progress.total) return
      files.set(progress.file, progress)
      let loaded = 0, total = 0
      for (const file of files.values()) {
        loaded += file.loaded
        total += file.total
      }
      self.postMessage({ type: "progress", percent: Math.round((100 * loaded) / total) })
    })

    self.postMessage({ type: "generating" })
    // 48 tokens ≈ 200 chars — enough headroom that the word-boundary trim
    // down to 160 lands on a sentence-ish clause instead of a stub.
    const [{ summary_text }] = await pipe(data.text,
      { min_new_tokens: 12, max_new_tokens: 48, truncation: true })
    self.postMessage({ type: "result", summary: summary_text })
  } catch (error) {
    summarizerPromise = undefined // a failed load must not poison retries
    self.postMessage({ type: "error", message: error?.message ?? String(error) })
  }
}
