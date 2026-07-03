import { Controller } from "@hotwired/stimulus"

// ARIA tabs. Click or arrow-key a tab to reveal its panel. Markup:
//   .tabs[data-controller=tabs]
//     .tabs__list[role=tablist][data-action="keydown->tabs#key"]
//       button.tabs__tab[role=tab][data-tabs-target=tab][data-action="click->tabs#show"]
//     .tabs__panel[role=tabpanel][data-tabs-target=panel]
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    const i = this.tabTargets.findIndex((t) => t.getAttribute("aria-selected") === "true")
    this.select(i < 0 ? 0 : i)
  }

  show(event) {
    this.select(this.tabTargets.indexOf(event.currentTarget))
    event.currentTarget.focus()
  }

  key(event) {
    const i = this.tabTargets.indexOf(document.activeElement)
    if (i < 0) return
    let next
    if (event.key === "ArrowRight") next = (i + 1) % this.tabTargets.length
    else if (event.key === "ArrowLeft") next = (i - 1 + this.tabTargets.length) % this.tabTargets.length
    else return
    event.preventDefault()
    this.select(next)
    this.tabTargets[next].focus()
  }

  select(index) {
    this.tabTargets.forEach((tab, i) => {
      const on = i === index
      tab.setAttribute("aria-selected", String(on))
      tab.tabIndex = on ? 0 : -1
    })
    this.panelTargets.forEach((panel, i) => { panel.hidden = i !== index })
  }
}
