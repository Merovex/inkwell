// Public-site JS entry — deliberately tiny (the marketing site stays JS-light).
// Ahoy tracks the visit on load and records a page-view event; because it runs
// in the browser, it counts edge-cached page loads that never reach Rails.
import ahoy from "ahoy"

ahoy.trackView()
