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

// Theme cycler: light → dark → auto, persisted as the public-only `press_theme`
// cookie (separate from the admin `theme` cookie; the layout renders it back
// as <html data-theme>, so no flash on next load). Delegated like the
// hamburger so it survives Turbo body swaps; both nav buttons stay in sync.
document.addEventListener("click", (event) => {
  const toggle = event.target.closest(".theme-toggle")
  if (!toggle) return
  const modes = ["light", "dark", "auto"]
  const current = document.documentElement.dataset.theme || "dark"
  const next = modes[(modes.indexOf(current) + 1) % modes.length]
  document.documentElement.dataset.theme = next
  document.cookie = `press_theme=${next}; path=/; max-age=31536000; samesite=lax`
  document.querySelectorAll(".theme-toggle").forEach((button) => {
    button.dataset.mode = next
    button.setAttribute("aria-label", `Theme: ${next}`)
  })
})

// TEMP heading-font audition: cycle the candidates alphabetically and persist
// as press_hfont; the layout renders it back as <html data-hfont>, which
// press-hfont.css maps to a font stack. Delete with the button when decided.
document.addEventListener("click", (event) => {
  const toggle = event.target.closest(".hfont-toggle")
  if (!toggle) return
  const fonts = ["antonio", "archivo-narrow"]
  const current = document.documentElement.dataset.hfont || "archivo-narrow"
  const next = fonts[(fonts.indexOf(current) + 1) % fonts.length]
  document.documentElement.dataset.hfont = next
  document.cookie = `press_hfont=${next}; path=/; max-age=31536000; samesite=lax`
  const label = next.split("-").map((word) => word === "pt" ? "PT" : word[0].toUpperCase() + word.slice(1)).join(" ")
  document.querySelectorAll(".hfont-toggle").forEach((button) => {
    button.textContent = label
    button.setAttribute("aria-label", `Heading font: ${next.replaceAll("-", " ")}`)
  })
})
