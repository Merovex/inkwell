import { Controller } from "@hotwired/stimulus"

// Switches a collection between layouts (e.g. list ⇄ cards) by writing
// data-view onto the collection element, and persists the choice in a cookie
// so it survives navigation — same pattern as the theme/tint toggles. Markup:
//   [data-controller=view-toggle data-view-toggle-name-value=circles_view]
//     .segmented
//       button[data-view=list][data-action="view-toggle#set"][data-view-toggle-target=button]
//       button[data-view=cards]…
//     ul[data-view-toggle-target=collection] (server sets the initial data-view)
export default class extends Controller {
  static targets = ["collection", "button"]
  static values = { name: String }

  set(event) {
    this.apply(event.currentTarget.dataset.view)
  }

  apply(view) {
    this.collectionTarget.dataset.view = view
    this.buttonTargets.forEach((b) => b.setAttribute("aria-selected", String(b.dataset.view === view)))
    document.cookie = `${this.nameValue}=${view}; path=/; max-age=31536000; samesite=lax`
  }
}
