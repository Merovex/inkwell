// Public-site JS entry — deliberately tiny (the marketing site stays JS-light).
// Ahoy tracks the visit on load and records a page-view event; because it runs
// in the browser, it counts edge-cached page loads that never reach Rails.
// ahoy.js ships as a UMD bundle (no ESM export) that assigns window.ahoy as a
// side effect — so import it for that effect and read the global, rather than
// `import ahoy from "ahoy"` (which throws "no export named 'default'").
import "ahoy"

window.ahoy.trackView()
