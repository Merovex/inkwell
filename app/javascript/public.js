// Public-site JS entry — deliberately tiny. Turbo Drive makes navigation feel
// instant: it swaps the <body> without a full document reload and, in Turbo 8,
// prefetches a link's target on hover/touch, so the next page is usually already
// fetched by the time it's clicked.
import "@hotwired/turbo-rails"

// Ahoy records a page-view event in the browser (so it counts edge-cached loads
// that never reach Rails). ahoy.js ships as a UMD bundle (no ESM export) that
// assigns window.ahoy as a side effect, so import it for that effect and read
// the global. Fire on turbo:load — which runs on the initial load AND after each
// Turbo navigation — so every page still gets counted now that nav is same-document.
import "ahoy"

document.addEventListener("turbo:load", () => window.ahoy.trackView())
