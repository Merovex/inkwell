import { Controller } from "@hotwired/stimulus"

// The SiteDesigner rail (ADR 0022, docs/site-designer.md). The working
// design lives in localStorage — scaffolding while the design.json schema
// settles; Save-to-press replaces it later. Every change debounces a
// stateless preview build (POST the design, Hugo renders it against real
// content) and reloads the iframe when the build lands.
// Until the nav block reaches the contract, these mirror the theme's own
// default links (baseof.html) — schema-lab duplication, settled at the
// contract bump.
const DEFAULT_LINKS = [
  { id: "books", label: "Books" },
  { id: "posts", label: "Posts" },
  { id: "about", label: "About" }
]
const BUILT_IN = DEFAULT_LINKS.map(link => link.id)
// Built-in destinations, shown read-only in the links editor (the theme owns
// the real paths; these are display values).
const BUILT_IN_PATHS = { books: "/books/", posts: "/posts/", about: "/about/" }

export default class extends Controller {
  static targets = ["frame", "stage", "status", "preset", "scaleNote", "pane",
    "linksList", "linkTemplate", "buttonLabel", "buttonUrl", "buttonNewTab",
    "buttonVisible", "buttonFields",
    "logoThumb", "logoRemove", "logoDropzone", "logoTitleWrap", "logoTitleAsAlt",
    "colorSlot", "colorChip", "assigning", "hexInput", "axisToggle", "axisSlider",
    "customFontCard", "customFontName", "customFontFamilies"]
  static values = {
    buildUrl: String, frameUrl: String, storageKey: String, defaults: Object,
    logoUrl: String,
    // Development live reload: poll versionUrl every watch ms and rebuild
    // when the theme tree changes. watch is 0 outside development.
    versionUrl: String, watch: Number
  }

  connect() {
    // Legacy stored shape was the flat axes hash; the current shape is
    // { design, nav }. Detect by the design key — in the flat shape, a
    // stored `nav` is the AXIS value (a string), not the content block.
    const stored = this.stored()
    const legacyFlat = !("design" in stored)
    this.design = { ...this.defaultsValue, ...(legacyFlat ? stored : stored.design) }
    this.nav = legacyFlat ? null : this.validNav(stored.nav)
    this.fonts = legacyFlat ? null : this.validFonts(stored.fonts)
    this.colors = legacyFlat ? null : this.validColors(stored.colors)
    // The remembered custom pairing outlives the active fonts block; older
    // stored states without the memory key seed it from the active block.
    this.customFonts = legacyFlat ? null
      : (this.validFonts(stored.custom_fonts) || this.validFonts(stored.fonts))
    this.updateCustomFontCard()
    this.applyToRail()
    this.refreshLabels()
    this.populateButtonFields()
    requestAnimationFrame(() => this.syncFontPickers())
    this.build()
    if (this.watchValue > 0) this.watcher = setInterval(() => this.checkTheme(), this.watchValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    clearInterval(this.watcher)
  }

  // Radio change: merge the rail's radio values over the design — MERGE,
  // never replace: switch-rendered axes (catalog, alternate) have no
  // radios, and a rebuild-from-radios would silently drop them back to
  // server defaults while the switches still display the old state.
  change(event) {
    this.design = { ...this.design, ...this.read() }
    // Picking a pairing (or palette) hands control back from the custom
    // escape valve: the custom override style ships after site.css and wins
    // at equal specificity, so a lingering fonts/colors block would keep
    // overriding every pairing/palette the author picks.
    const axis = event?.target?.name?.match(/^design\[(.+)\]$/)?.[1]
    if (axis === "font" && this.fonts) {
      this.fonts = null
      this.syncFontPickers()
    }
    if (axis === "palette" && this.colors) {
      this.colors = null
      this.workingColors = {}
      this.paintColorSlots()
    }
    this.store()
    this.refreshLabels()
    this.scheduleBuild()
  }

  applyPreset(event) {
    this.design = { ...this.defaultsValue, ...event.params.axes }
    // A preset is the whole design — custom fonts/colors would override
    // its pairing and palette, so they hand control back too.
    this.fonts = null
    this.colors = null
    this.workingColors = {}
    this.syncFontPickers()
    this.paintColorSlots()
    this.store()
    this.applyToRail()
    this.refreshLabels()
    this.scheduleBuild()
  }

  reset() {
    localStorage.removeItem(this.storageKeyValue)
    this.design = { ...this.defaultsValue }
    this.nav = null
    this.fonts = null
    this.customFonts = null
    this.colors = null
    this.workingColors = null
    this.updateCustomFontCard()
    this.applyToRail()
    this.refreshLabels()
    this.populateButtonFields()
    this.syncFontPickers()
    if (this.hasLinksListTarget) this.renderLinks()
    this.scheduleBuild()
  }

  // --- header links + button (the nav content block; popover editors)

  openLinks() {
    this.renderLinks()
  }

  addLink() {
    this.ensureNav()
    this.nav.links.push({ id: `custom-${crypto.randomUUID().slice(0, 8)}`, label: "", url: "", visible: true })
    this.renderLinks()
    this.commit()
  }

  removeLink(event) {
    this.ensureNav()
    this.nav.links.splice(this.rowIndex(event.target), 1)
    this.renderLinks()
    this.commit()
  }

  moveLink(event) {
    this.ensureNav()
    const from = this.rowIndex(event.target)
    const to = from + event.params.dir
    if (to < 0 || to >= this.nav.links.length) return
    const [moved] = this.nav.links.splice(from, 1)
    this.nav.links.splice(to, 0, moved)
    this.renderLinks()
    this.commit()
  }

  linksEdited() {
    this.ensureNav()
    this.nav.links = [...this.linksListTarget.children].map(row => {
      const link = {
        id: row.dataset.id,
        label: row.querySelector("[data-field=label]").value,
        visible: row.querySelector("[data-field=visible]").checked
      }
      if (!BUILT_IN.includes(link.id)) link.url = row.querySelector("[data-field=url]").value
      return link
    })
    this.commit()
  }

  // Three button states: hidden ({visible:false} — no CTA at all), custom
  // ({label,url}), or null (the theme's newsletter default).
  buttonEdited() {
    this.ensureNav()
    const visible = this.buttonVisibleTarget.checked
    this.buttonFieldsTarget.disabled = !visible
    if (visible) {
      const label = this.buttonLabelTarget.value.trim()
      const url = this.buttonUrlTarget.value.trim()
      this.nav.button = (label && url) ? { label, url, new_tab: this.buttonNewTabTarget.checked } : null
    } else {
      this.nav.button = { visible: false }
    }
    this.commit()
  }

  // --- the header logo (persists to the Site immediately — binaries can't
  //     ride localStorage; the exporter reads the attachment)

  uploadLogo(event) {
    const file = event.target.files[0]
    if (file) this.sendLogo(file)
    event.target.value = ""
  }

  logoDragOver(event) {
    event.preventDefault()
    this.logoDropzoneTarget.classList.add("is-dragover")
  }

  logoDragLeave(event) {
    if (!this.logoDropzoneTarget.contains(event.relatedTarget)) {
      this.logoDropzoneTarget.classList.remove("is-dragover")
    }
  }

  logoTitleEdited() {
    this.ensureNav()
    this.nav.title_as_alt = this.logoTitleAsAltTarget.checked
    this.commit()
  }

  // --- custom palette: authors pick COLORS per role — wheel presets or
  //     free hex, one pipeline; the server keeps only chroma + hue and
  //     drives lightness per role/mode. Partial picks stay local; the
  //     server only sees a complete trio.

  openColors() {
    this.workingColors = { ...(this.validColors(this.colors) || {}) }
    this.paintColorSlots()
    this.syncHexInput()
  }

  selectColorSlot(event) {
    this.colorSlotTargets.forEach(slot => slot.classList.toggle("is-active", slot === event.currentTarget))
    this.updateAssigning()
    this.syncHexInput()
  }

  colorPicked(event) {
    this.assignColor(event.params.hex, event.target.closest(".designer__hue")?.getAttribute("aria-label"))
  }

  // Free entry: normalize to one leading # + up to six hex digits; assign
  // once complete.
  hexEdited() {
    const hex = `#${this.hexInputTarget.value.replaceAll("#", "").replace(/[^0-9a-fA-F]/g, "").slice(0, 6).toLowerCase()}`
    this.hexInputTarget.value = hex
    if (/^#[0-9a-f]{6}$/.test(hex)) this.assignColor(hex, hex)
  }

  // No auto-advance: the hex field always reflects the ACTIVE slot, so a
  // wheel pick must stay on its slot for its hex to be visible.
  assignColor(hex, label) {
    const active = this.colorSlotTargets.find(slot => slot.classList.contains("is-active"))
    if (!active) return
    this.workingColors[active.dataset.slot] = hex
    this.paintColorSlots()
    this.updateAssigning(label)
    this.syncHexInput()
    this.commitColors()
  }

  syncHexInput() {
    if (!this.hasHexInputTarget) return
    const active = this.colorSlotTargets.find(slot => slot.classList.contains("is-active"))
    if (document.activeElement !== this.hexInputTarget) {
      this.hexInputTarget.value = this.workingColors?.[active?.dataset.slot] || ""
    }
  }

  hueHovered(event) {
    const hue = event.target.closest(".designer__hue")?.getAttribute("aria-label")
    if (hue) this.updateAssigning(hue)
  }

  hueLeft() {
    this.updateAssigning()
  }

  updateAssigning(hue = null) {
    if (!this.hasAssigningTarget) return
    const active = this.colorSlotTargets.find(slot => slot.classList.contains("is-active"))
    const role = active ? active.textContent.trim() : "…"
    // Title-case the hue names (hexes pass through unchanged).
    const title = hue ? hue.charAt(0).toUpperCase() + hue.slice(1) : null
    this.assigningTarget.textContent = `Assigning: ${role}${title ? ` · ${title}` : ""}`
  }

  clearColors() {
    this.colors = null
    this.workingColors = {}
    this.paintColorSlots()
    this.commit()
    this.refreshLabels()
  }

  commitColors() {
    const { bg, accent, ink } = this.workingColors
    this.colors = (bg && accent && ink) ? { ...this.workingColors } : null
    this.commit()
    this.refreshLabels()
  }

  // Chips show the picked color itself (its identity); the preview shows
  // the role-and-mode shades the server derives from it.
  paintColorSlots() {
    this.colorChipTargets.forEach(chip => {
      const hex = this.workingColors?.[chip.dataset.slot]
      chip.style.background = hex || "transparent"
      chip.classList.toggle("is-empty", !hex)
    })
  }

  validColors(colors) {
    if (!colors || typeof colors !== "object") return null
    const hex = value => /^#[0-9a-f]{6}$/i.test(value || "")
    return (hex(colors.bg) && hex(colors.accent) && hex(colors.ink)) ? colors : null
  }

  // --- custom fonts (the escape valve; picks arrive from font-picker)

  customFontPicked(event) {
    const { slot, family } = event.detail
    this.fonts = { ...(this.validFonts(this.fonts) || {}), [slot]: family }
    this.customFonts = { ...this.fonts }
    this.updateCustomFontCard()
    this.applyToRail()
    this.commit()
    this.refreshLabels()
  }

  clearCustomFonts() {
    this.fonts = null
    this.syncFontPickers()
    this.applyToRail()
    this.commit()
    this.refreshLabels()
  }

  // The memory card: reactivate the remembered custom pairing.
  customFontCardPicked() {
    this.fonts = this.validFonts(this.customFonts) ? { ...this.customFonts } : null
    this.syncFontPickers()
    this.store()
    this.refreshLabels()
    this.scheduleBuild()
  }

  updateCustomFontCard() {
    if (!this.hasCustomFontCardTarget) return
    const memory = this.validFonts(this.customFonts)
    this.customFontCardTarget.hidden = !memory
    if (!memory) return
    const { display, body } = memory
    if (display) this.loadFace(display)
    if (body) this.loadFace(body)
    this.customFontNameTarget.style.fontFamily = display ? `'${display}', serif` : ""
    this.customFontFamiliesTarget.style.fontFamily = body ? `'${body}', serif` : ""
    this.customFontFamiliesTarget.textContent = [display, body].filter(Boolean).join(" + ")
  }

  // Same dedup'd stylesheet injection the font picker uses for its input
  // preview (shared link ids, so neither loads a face twice).
  loadFace(family) {
    const id = `gf-preview-${family.replaceAll(" ", "-")}`
    if (document.getElementById(id)) return
    document.head.append(Object.assign(document.createElement("link"), {
      id, rel: "stylesheet",
      href: `https://fonts.googleapis.com/css2?family=${family.replaceAll(" ", "+")}&display=swap`
    }))
  }

  validFonts(fonts) {
    if (!fonts || typeof fonts !== "object") return null
    return (typeof fonts.display === "string" || typeof fonts.body === "string") ? fonts : null
  }

  syncFontPickers() {
    this.element.querySelectorAll(".font-picker").forEach(el => {
      const picker = this.application.getControllerForElementAndIdentifier(el, "font-picker")
      picker?.display(this.fonts?.[el.dataset.fontPickerSlotValue])
    })
  }

  logoDrop(event) {
    event.preventDefault()
    this.logoDropzoneTarget.classList.remove("is-dragover")
    const file = event.dataTransfer.files[0]
    if (file) this.sendLogo(file)
  }

  async sendLogo(file) {
    this.statusTarget.textContent = "Uploading logo…"
    const body = new FormData()
    body.append("logo", file)
    const response = await fetch(this.logoUrlValue, { method: "PATCH", headers: { "X-CSRF-Token": this.csrf }, body })

    if (response.ok) {
      const { url } = await response.json()
      this.logoThumbTarget.src = url
      this.logoThumbTarget.hidden = false
      this.logoRemoveTarget.hidden = false
      this.logoTitleWrapTarget.hidden = false
      this.build()
    } else {
      const failure = await response.json().catch(() => ({}))
      this.statusTarget.textContent = failure.error || "Logo upload failed"
    }
  }

  async removeLogo() {
    await fetch(this.logoUrlValue, { method: "DELETE", headers: { "X-CSRF-Token": this.csrf } })
    this.logoThumbTarget.hidden = true
    this.logoThumbTarget.removeAttribute("src")
    this.logoRemoveTarget.hidden = true
    this.logoTitleWrapTarget.hidden = true
    this.build()
  }

  // --- rail pane navigation (no routing; panes show/hide, teardown-style)

  showPane(event) {
    this.paneTargets.forEach(pane => pane.hidden = pane.dataset.pane !== event.params.pane)
  }

  back() {
    this.paneTargets.forEach(pane => pane.hidden = pane.dataset.pane !== "root")
  }

  viewport(event) {
    this.stageTarget.dataset.viewport = event.params.width
    this.scaleNoteTarget.textContent = event.params.width === "desktop" ? "Preview shown at 70%." : "Preview at full size."
    this.element.querySelectorAll(".designer__viewport").forEach(button => {
      button.classList.toggle("is-active", button === event.target)
      button.setAttribute("aria-pressed", button === event.target ? "true" : "false")
    })
  }

  // --- internals

  stored() {
    try {
      return JSON.parse(localStorage.getItem(this.storageKeyValue)) || {}
    } catch {
      return {}
    }
  }

  store() {
    localStorage.setItem(this.storageKeyValue,
      JSON.stringify({ design: this.design, nav: this.nav, fonts: this.fonts, colors: this.colors,
        custom_fonts: this.customFonts }))
  }

  // Only a well-shaped block counts — a nav axis value ("split") once leaked
  // into stored state here, and anything malformed must fall back to defaults.
  validNav(nav) {
    return (nav && typeof nav === "object" && Array.isArray(nav.links)) ? nav : null
  }

  ensureNav() {
    this.nav = this.validNav(this.nav) || { links: structuredClone(DEFAULT_LINKS), button: null }
  }

  commit() {
    this.store()
    this.scheduleBuild()
  }

  rowIndex(element) {
    return [...this.linksListTarget.children].indexOf(element.closest(".designer__link-row"))
  }

  renderLinks() {
    this.ensureNav()
    this.linksListTarget.replaceChildren()
    this.nav.links.forEach(link => {
      const row = this.linkTemplateTarget.content.firstElementChild.cloneNode(true)
      row.dataset.id = link.id
      row.querySelector("[data-field=label]").value = link.label || ""
      row.querySelector("[data-field=visible]").checked = link.visible !== false
      const url = row.querySelector("[data-field=url]")
      if (BUILT_IN.includes(link.id)) {
        url.value = BUILT_IN_PATHS[link.id]
        url.disabled = true
        url.title = "Built-in page"
        row.querySelector(".designer__link-remove").remove()
      } else {
        url.value = link.url || ""
      }
      this.linksListTarget.append(row)
    })
  }

  populateButtonFields() {
    if (!this.hasButtonLabelTarget) return
    const visible = this.nav?.button?.visible !== false
    this.buttonVisibleTarget.checked = visible
    this.buttonFieldsTarget.disabled = !visible
    this.buttonLabelTarget.value = this.nav?.button?.label || ""
    this.buttonUrlTarget.value = this.nav?.button?.url || ""
    this.buttonNewTabTarget.checked = this.nav?.button?.new_tab || false
    if (this.hasLogoTitleAsAltTarget) this.logoTitleAsAltTarget.checked = this.nav?.title_as_alt !== false
  }

  read() {
    const design = {}
    this.radios().forEach(radio => {
      // The custom-pairing memory card rides the font radio group for
      // mutual exclusion, but its value is not a design axis value.
      if (radio.checked && !("customFont" in radio.dataset)) design[this.axisOf(radio)] = radio.value
    })
    return design
  }

  applyToRail() {
    // The custom card checks when the custom block is active; it sits last
    // in the group, so checking it unchecks the pairing radio (and vice
    // versa — the browser handles the group).
    this.radios().forEach(radio => radio.checked = "customFont" in radio.dataset
      ? !!this.validFonts(this.fonts)
      : this.design[this.axisOf(radio)] === radio.value)
    this.axisToggleTargets.forEach(toggle => toggle.checked = this.design[toggle.dataset.axis] === toggle.dataset.on)
    this.axisSliderTargets.forEach(slider =>
      slider.value = Math.max(0, slider.dataset.options.split(",").indexOf(this.design[slider.dataset.axis])))
  }

  // Ordered-scale axes render as sliders: the position indexes the options.
  axisSlid(event) {
    const slider = event.target
    this.design[slider.dataset.axis] = slider.dataset.options.split(",")[slider.value]
    this.store()
    this.refreshLabels()
    this.scheduleBuild()
  }

  // Boolean-ish axes render as switches: on/off map to the two option ids.
  axisToggled(event) {
    const toggle = event.target
    this.design[toggle.dataset.axis] = toggle.checked ? toggle.dataset.on : toggle.dataset.off
    this.store()
    this.refreshLabels()
    this.scheduleBuild()
  }

  radios() {
    return this.element.querySelectorAll(".design-option__input")
  }

  axisOf(radio) {
    return radio.name.slice("design[".length, -1)
  }

  // Every current-value label in the root menu: per-axis summaries (the
  // checked option's label) and the derived preset name (compare against
  // each preset button's axes; no exact match reads as Custom — derived,
  // never stored).
  refreshLabels() {
    this.element.querySelectorAll("[data-summary-for]").forEach(summary => {
      const checked = this.element.querySelector(`input[name="design[${summary.dataset.summaryFor}]"]:checked`)
      summary.textContent = checked?.dataset.label ||
        checked?.parentElement.querySelector(".design-option__label")?.textContent.trim() || "—"
    })

    // Row chips (wireframe/swatch thumbnails) show the current option.
    this.element.querySelectorAll("[data-chip-for]").forEach(chip => {
      const current = this.design[chip.dataset.chipFor]
      chip.querySelectorAll("[data-option]").forEach(option => option.hidden = option.dataset.option !== current)
    })

    // Switch- and slider-rendered axes have no radios — summarize from
    // their labels (all matching spans: the row AND the pane control).
    const summarize = (axis, text) =>
      this.element.querySelectorAll(`[data-summary-for="${axis}"]`).forEach(span => span.textContent = text)
    this.axisToggleTargets.forEach(toggle =>
      summarize(toggle.dataset.axis,
        this.design[toggle.dataset.axis] === toggle.dataset.on ? toggle.dataset.onLabel : toggle.dataset.offLabel))
    this.axisSliderTargets.forEach(slider => {
      const index = Math.max(0, slider.dataset.options.split(",").indexOf(this.design[slider.dataset.axis]))
      summarize(slider.dataset.axis, slider.dataset.labels.split(",")[index])
    })

    // Custom fonts / colors trump the pairing / palette in the summaries.
    if (this.validFonts(this.fonts)) {
      const summary = this.element.querySelector('[data-summary-for="font"]')
      if (summary) summary.textContent = "Custom"
    }
    if (this.validColors(this.colors)) {
      const summary = this.element.querySelector('[data-summary-for="palette"]')
      if (summary) summary.textContent = "Custom"
    }

    if (!this.hasPresetTarget) return
    const match = [...this.element.querySelectorAll(".designer__preset")].find(button => {
      const axes = JSON.parse(button.dataset.designerAxesParam)
      return Object.entries(axes).every(([key, value]) => this.design[key] === value)
    })
    this.presetTarget.textContent = match ? match.textContent.trim() : "Custom"
  }

  scheduleBuild() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.build(), 500)
  }

  async checkTheme() {
    if (this.building) return

    const response = await fetch(this.versionUrlValue).catch(() => null)
    if (!response?.ok) return

    const { version } = await response.json()
    if (this.themeVersion && version !== this.themeVersion) this.build()
    this.themeVersion = version
  }

  async build() {
    this.building = true
    this.statusTarget.textContent = "Building preview…"
    const response = await fetch(this.buildUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf },
      body: JSON.stringify({ design: this.design, nav: this.nav, fonts: this.fonts, colors: this.colors })
    })

    if (response.ok) {
      this.reloadFrame()
      this.statusTarget.textContent = `Preview updated ${new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`
    } else {
      const failure = await response.json().catch(() => ({}))
      this.statusTarget.textContent = failure.error || "Preview build failed"
    }
    this.building = false
  }

  get csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  // Keep the author's place: reload in situ once the iframe holds the site;
  // point it at the preview root only on the first build.
  reloadFrame() {
    if (this.frameTarget.src && !this.frameTarget.src.endsWith("about:blank")) {
      this.frameTarget.contentWindow.location.reload()
    } else {
      this.frameTarget.src = this.frameUrlValue
    }
  }
}
