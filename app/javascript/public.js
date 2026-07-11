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

// Mobile nav hamburger. Delegated so it survives Turbo body swaps; each
// navigation renders a fresh (closed) menu, so there's no state to clean up.
document.addEventListener("click", (event) => {
  const toggle = event.target.closest(".press-nav__toggle")
  if (!toggle) return
  const menu = document.getElementById(toggle.getAttribute("aria-controls"))
  const open = toggle.getAttribute("aria-expanded") === "true"
  toggle.setAttribute("aria-expanded", String(!open))
  menu.hidden = open
})

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return
  const toggle = document.querySelector('.press-nav__toggle[aria-expanded="true"]')
  if (!toggle) return
  toggle.setAttribute("aria-expanded", "false")
  document.getElementById(toggle.getAttribute("aria-controls")).hidden = true
})
