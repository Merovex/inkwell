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
// The theme's home.sections default order (home.html) — same schema-lab
// duplication deal as DEFAULT_LINKS.
const DEFAULT_SECTIONS = ["hero", "books", "posts", "bio", "authors", "newsletter"]

export default class extends Controller {
  static targets = ["frame", "stage", "status", "preset", "scaleNote", "pane",
    "linksList", "linkTemplate", "buttonLabel", "buttonUrl", "buttonNewTab",
    "buttonVisible", "buttonFields",
    "logoTitleWrap", "logoTitleAsAlt",
    "colorSlot", "colorChip", "assigning", "hexInput", "axisToggle", "axisSlider", "buttonDemo",
    "customFontCard", "customFontName", "customFontFamilies",
    "heroHeadline", "heroLede", "heroBook", "heroSource", "heroCustomFields", "heroBookWrap",
    "heroLedeCount", "heroManyWrap", "heroScrimWrap", "heroScrimColor",
    "nlHeadline", "nlBlurb", "nlButton", "orderList", "footerFinePrint"]
  static values = {
    buildUrl: String, frameUrl: String, storageKey: String, defaults: Object,
    saveUrl: String,
    // Image-slot endpoint template; __SLOT__ is replaced per upload.
    imagesUrl: String,
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
    // Schema-lab migrations: scrim/blur/3d graduated from hero LAYOUTS to
    // the orthogonal hero_book / hero_bg axes; then the layouts collapsed
    // to none/centered/right/many (split & duet → right, fan → many,
    // name → none).
    const graduated = {
      scrim: { hero: "right", hero_bg: "scrim" },
      blur: { hero: "right", hero_bg: "cover" },
      "3d": { hero: "right", hero_book: "3d", hero_bg: "cover" },
      split: { hero: "right" },
      duet: { hero: "right" },
      fan: { hero: "many" },
      name: { hero: "none" }
    }[this.design.hero]
    if (graduated) this.design = { ...this.design, ...graduated }
    this.nav = legacyFlat ? null : this.validNav(stored.nav)
    this.fonts = legacyFlat ? null : this.validFonts(stored.fonts)
    this.colors = legacyFlat ? null : this.validColors(stored.colors)
    // The remembered custom pairing outlives the active fonts block; older
    // stored states without the memory key seed it from the active block.
    this.customFonts = legacyFlat ? null
      : (this.validFonts(stored.custom_fonts) || this.validFonts(stored.fonts))
    this.hero = legacyFlat ? null : this.validHero(stored.hero)
    this.newsletter = legacyFlat ? null : this.validNewsletter(stored.newsletter)
    this.footer = legacyFlat ? null : this.validFooter(stored.footer)
    this.sections = legacyFlat ? null : this.validSections(stored.sections)
    this.updateCustomFontCard()
    this.applyToRail()
    this.refreshLabels()
    this.populateButtonFields()
    this.populateHeroFields()
    this.populateNewsletterFields()
    this.populateFooterFields()
    this.populateSectionOrder()
    this.updateModeToggle()
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
    // escape valve: the custom override style ships after the css modules and wins
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
    this.hero = null
    this.newsletter = null
    this.footer = null
    this.sections = null
    this.updateCustomFontCard()
    this.populateHeroFields()
    this.populateNewsletterFields()
    this.populateFooterFields()
    this.populateSectionOrder()
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

  // --- the Site's image slots (logo / banner / newsletter photo): one
  //     generic dropzone mechanism keyed by data-designer-slot; persists
  //     immediately — binaries can't ride localStorage, the exporter reads
  //     the attachments.

  imagePicked(event) {
    const file = event.target.files[0]
    if (file) this.sendImage(this.slotOf(event), file)
    event.target.value = ""
  }

  imageDragOver(event) {
    event.preventDefault()
    event.currentTarget.classList.add("is-dragover")
  }

  imageDragLeave(event) {
    if (!event.currentTarget.contains(event.relatedTarget)) {
      event.currentTarget.classList.remove("is-dragover")
    }
  }

  imageDrop(event) {
    event.preventDefault()
    event.currentTarget.classList.remove("is-dragover")
    const file = event.dataTransfer.files[0]
    if (file) this.sendImage(this.slotOf(event), file)
  }

  async sendImage(slot, file) {
    this.statusTarget.textContent = "Uploading image…"
    const body = new FormData()
    body.append(slot, file)
    const response = await fetch(this.imageUrl(slot), { method: "PATCH", headers: { "X-CSRF-Token": this.csrf }, body })

    if (response.ok) {
      const { url } = await response.json()
      const zone = this.zone(slot)
      const thumb = zone.querySelector("[data-image-role=thumb]")
      thumb.src = url
      thumb.hidden = false
      zone.querySelector("[data-image-role=remove]").hidden = false
      if (slot === "logo") this.logoTitleWrapTarget.hidden = false
      this.build()
    } else {
      const failure = await response.json().catch(() => ({}))
      this.statusTarget.textContent = failure.error || "Image upload failed"
    }
  }

  async removeImage(event) {
    const slot = this.slotOf(event)
    await fetch(this.imageUrl(slot), { method: "DELETE", headers: { "X-CSRF-Token": this.csrf } })
    const zone = this.zone(slot)
    const thumb = zone.querySelector("[data-image-role=thumb]")
    thumb.hidden = true
    thumb.removeAttribute("src")
    zone.querySelector("[data-image-role=remove]").hidden = true
    if (slot === "logo") this.logoTitleWrapTarget.hidden = true
    this.build()
  }

  slotOf(event) {
    return event.target.closest("[data-designer-slot]").dataset.designerSlot
  }

  zone(slot) {
    return this.element.querySelector(`[data-designer-slot="${slot}"]`)
  }

  imageUrl(slot) {
    return this.imagesUrlValue.replace("__SLOT__", slot)
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

  // --- hero content (the element editor: headline / intro / featured book;
  //     blank fields keep the fed defaults, so the block is override-only)

  heroEdited() {
    const hero = {}
    const source = this.heroSourceTargets.find(radio => radio.checked)?.value || "author"
    if (source !== "author") hero.source = source
    if (this.heroHeadlineTarget.value.trim()) hero.headline = this.heroHeadlineTarget.value.trim()
    const ledeHtml = this.heroLedeTarget.value || ""
    if (this.heroPlainText(ledeHtml)) hero.lede_html = ledeHtml
    if (this.heroBookTarget.value) hero.book = this.heroBookTarget.value
    // Scrim tint over image backdrops; black is the built-in default, so we
    // only carry an explicit, non-black pick (keeps the block override-only).
    if (this.hasHeroScrimColorTarget) {
      const color = this.heroScrimColorTarget.value
      if (color && color.toLowerCase() !== "#000000") hero.scrim_color = color
    }
    this.hero = Object.keys(hero).length ? hero : null
    this.heroCustomFieldsTarget.hidden = source !== "custom"
    this.updateHeroCount()
    this.commit()
  }

  populateHeroFields() {
    if (!this.hasHeroHeadlineTarget) return
    // Legacy working states carried plain hero.lede; the field is rich now.
    if (this.hero?.lede && !this.hero.lede_html) {
      const escaped = this.hero.lede.replace(/&/g, "&amp;").replace(/</g, "&lt;")
      this.hero = { ...this.hero, lede_html: `<p>${escaped}</p>` }
      delete this.hero.lede
    }
    const source = this.hero?.source || "author"
    this.heroSourceTargets.forEach(radio => radio.checked = radio.value === source)
    this.heroCustomFieldsTarget.hidden = source !== "custom"
    this.heroHeadlineTarget.value = this.hero?.headline || ""
    this.heroLedeTarget.value = this.hero?.lede_html || ""
    this.heroBookTarget.value = this.hero?.book || ""
    if (this.hasHeroScrimColorTarget) this.heroScrimColorTarget.value = this.hero?.scrim_color || "#000000"
    this.updateHeroCount()
  }

  // The soft text budget: 160 characters, deliberately un-enforced —
  // "170/160" is a nudge, not a wall.
  updateHeroCount() {
    if (!this.hasHeroLedeCountTarget) return
    const count = this.heroPlainText(this.heroLedeTarget.value || "").length
    this.heroLedeCountTarget.textContent = `${count}/160`
    this.heroLedeCountTarget.classList.toggle("designer__count--over", count > 160)
  }

  heroPlainText(html) {
    return new DOMParser().parseFromString(html, "text/html").body.textContent.trim()
  }

  validHero(hero) {
    if (!hero || typeof hero !== "object") return null
    const filled = ["source", "headline", "lede", "lede_html", "book", "scrim_color"].some(key => typeof hero[key] === "string" && hero[key])
    return filled ? hero : null
  }

  // --- save (graduate the working design from the browser to the account,
  //     where the next real build reads it; deliberate, never autosave \u2014 an
  //     idle drag must not republish a live site)

  async save() {
    this.statusTarget.textContent = "Saving\u2026"
    const response = await fetch(this.saveUrlValue, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf },
      body: JSON.stringify(this.payload())
    })
    if (response.ok) {
      this.statusTarget.textContent = `Saved ${new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}`
    } else {
      const failure = await response.json().catch(() => ({}))
      this.statusTarget.textContent = failure.error || "Couldn't save the design"
    }
  }

  // --- home section order (the home.sections contract field; the root
  //     menu's Page sections rows are the order — drag a handle or press
  //     an arrow key on it, the DOM is the state). Hero isn't a row here
  //     (it has the featured card): it stays the page opener, pinned first
  //     in the emitted order.

  sectionDragStart(event) {
    this.draggedSection = event.target.closest("[data-section]")
    this.draggedSection.classList.add("is-dragging")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedSection.dataset.section)
    event.dataTransfer.setDragImage(this.draggedSection, 24, 24)
  }

  // Rows reorder live as the drag passes their midpoints; dragend commits.
  sectionDragOver(event) {
    if (!this.draggedSection) return
    event.preventDefault()
    const over = event.target.closest("[data-section]")
    if (!over || over === this.draggedSection) return
    const midpoint = over.getBoundingClientRect().top + over.offsetHeight / 2
    event.clientY > midpoint ? over.after(this.draggedSection) : over.before(this.draggedSection)
  }

  sectionDragEnd() {
    if (!this.draggedSection) return
    this.draggedSection.classList.remove("is-dragging")
    this.draggedSection = null
    this.commitSectionOrder()
  }

  sectionKeydown(event) {
    const dir = { ArrowUp: -1, ArrowDown: 1 }[event.key]
    if (!dir) return
    event.preventDefault()
    const row = event.target.closest("[data-section]")
    const sibling = dir < 0 ? row.previousElementSibling : row.nextElementSibling
    if (!sibling) return
    dir < 0 ? sibling.before(row) : sibling.after(row)
    event.target.focus()
    this.commitSectionOrder()
  }

  commitSectionOrder() {
    this.sections = ["hero", ...[...this.orderListTarget.children].map(row => row.dataset.section)]
    if (this.sections.join() === DEFAULT_SECTIONS.join()) this.sections = null
    this.commit()
  }

  populateSectionOrder() {
    if (!this.hasOrderListTarget) return
    const order = this.validSections(this.sections) || DEFAULT_SECTIONS
    order.forEach(id => {
      const row = this.orderListTarget.querySelector(`[data-section="${id}"]`)
      if (row) this.orderListTarget.append(row)
    })
  }

  validSections(sections) {
    if (!Array.isArray(sections)) return null
    return [...sections].sort().join() === [...DEFAULT_SECTIONS].sort().join() ? sections : null
  }

  // --- newsletter copy (the email-collection block; override-only)

  newsletterEdited() {
    const block = {}
    if (this.nlHeadlineTarget.value.trim()) block.headline = this.nlHeadlineTarget.value.trim()
    if (this.nlBlurbTarget.value.trim()) block.blurb = this.nlBlurbTarget.value.trim()
    if (this.nlButtonTarget.value.trim()) block.button_label = this.nlButtonTarget.value.trim()
    this.newsletter = Object.keys(block).length ? block : null
    this.commit()
  }

  populateNewsletterFields() {
    if (!this.hasNlHeadlineTarget) return
    this.nlHeadlineTarget.value = this.newsletter?.headline || ""
    this.nlBlurbTarget.value = this.newsletter?.blurb || ""
    this.nlButtonTarget.value = this.newsletter?.button_label || ""
  }

  validNewsletter(block) {
    if (!block || typeof block !== "object") return null
    const filled = ["headline", "blurb", "button_label"].some(key => typeof block[key] === "string" && block[key])
    return filled ? block : null
  }

  // --- footer content (the fine-print override — layout and visibility
  //     are footer_* axes; social links are Site settings, not design)

  footerEdited() {
    const fine_print = this.footerFinePrintTarget.value.trim()
    this.footer = fine_print ? { fine_print } : null
    this.commit()
  }

  populateFooterFields() {
    if (!this.hasFooterFinePrintTarget) return
    this.footerFinePrintTarget.value = this.footer?.fine_print || ""
  }

  validFooter(block) {
    if (!block || typeof block !== "object" || Array.isArray(block)) return null
    return (typeof block.fine_print === "string" && block.fine_print) ? { fine_print: block.fine_print } : null
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


  // --- rail pane navigation (no routing; panes show/hide, teardown-style)

  showPane(event) {
    this.paneTargets.forEach(pane => pane.hidden = pane.dataset.pane !== event.params.pane)
  }

  back() {
    this.paneTargets.forEach(pane => pane.hidden = pane.dataset.pane !== "root")
  }

  // --- preview-only mode peek: forces the iframe's data-mode so the
  //     author can check both renditions without changing the design's
  //     mode axis. Cleared by nothing — it's a viewing control.

  previewMode(event) {
    this.previewModeChoice = event.params.mode
    this.applyPreviewMode()
    this.updateModeToggle()
  }

  applyPreviewMode() {
    const root = this.frameTarget.contentDocument?.documentElement
    if (root && this.previewModeChoice) root.dataset.mode = this.previewModeChoice
  }

  frameLoaded() {
    this.applyPreviewMode()
  }

  // Pressed state tracks the forced peek, or the design's effective mode
  // (auto = the admin's own OS) until the author clicks.
  updateModeToggle() {
    const effective = this.previewModeChoice ||
      (this.design.mode !== "auto" ? this.design.mode
        : (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"))
    this.element.querySelectorAll(".designer__preview-mode").forEach(button => {
      const active = button.dataset.designerModeParam === effective
      button.classList.toggle("is-active", active)
      button.setAttribute("aria-pressed", String(active))
    })
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
        custom_fonts: this.customFonts, hero: this.hero, newsletter: this.newsletter,
        footer: this.footer, sections: this.sections }))
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
    // Only design-axis radios: option-card styling is also worn by
    // non-axis controls (the hero copy-source picker).
    return this.element.querySelectorAll('.design-option__input[name^="design["]')
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

    // The Buttons pane's sample buttons and the footer's paper/ink cards:
    // shapes from the working design; colors from the custom-color block
    // when set, else the current palette's swatches (read off the root
    // row's chip). Swatches are ordered artistically — dominant color
    // first, accent always middle — so paper and ink are derived by
    // lightness, not position. The custom properties land on the designer
    // root so the option-card depictions paint in the same colors.
    if (this.hasButtonDemoTarget) {
      const demo = this.buttonDemoTarget
      demo.dataset.rounding = this.design.buttons
      demo.dataset.second = this.design.button_second
      demo.dataset.size = this.design.button_size
      const custom = this.validColors(this.colors)
      const swatch = index => this.element.querySelector(
        `[data-chip-for="palette"] [data-option="${this.design.palette}"] .designer__swatch:nth-child(${index})`)?.style.background
      const luminance = color => {
        const [r, g, b] = (color.match(/\d+/g) || [0, 0, 0]).map(Number)
        return r * 0.299 + g * 0.587 + b * 0.114
      }
      const trio = [swatch(1), swatch(2), swatch(3)].filter(Boolean)
      const paper = custom?.bg || (trio.length && trio.reduce((a, b) => luminance(a) >= luminance(b) ? a : b))
      const ink = custom?.ink || (trio.length && trio.reduce((a, b) => luminance(a) <= luminance(b) ? a : b))
      const accent = custom?.accent || swatch(2)
      if (paper) this.element.style.setProperty("--demo-bg", paper)
      if (accent) this.element.style.setProperty("--demo-accent", accent)
      if (ink) this.element.style.setProperty("--demo-ink", ink)
    }

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
    // The Fonts row's typeface names describe the pairing, so they hide
    // wholesale when a custom pairing takes over.
    this.element.querySelectorAll("[data-font-names]")
      .forEach(names => names.hidden = this.validFonts(this.fonts))
    if (this.validFonts(this.fonts)) {
      const summary = this.element.querySelector('[data-summary-for="font"]')
      if (summary) summary.textContent = "Custom"
    }
    if (this.validColors(this.colors)) {
      const summary = this.element.querySelector('[data-summary-for="palette"]')
      if (summary) summary.textContent = "Custom"
    }

    this.updateModeToggle()

    // Conditional hero controls: the 3D switch wants a one-book layout,
    // the stagger switch wants Many books, the scrim slider an image
    // backdrop.
    if (this.hasHeroBookWrapTarget) {
      this.heroBookWrapTarget.hidden = !["centered", "right"].includes(this.design.hero)
    }
    if (this.hasHeroManyWrapTarget) {
      this.heroManyWrapTarget.hidden = this.design.hero !== "many"
    }
    if (this.hasHeroScrimWrapTarget) {
      this.heroScrimWrapTarget.hidden = !["cover", "banner"].includes(this.design.hero_bg)
    }

    if (!this.hasPresetTarget) return
    const match = [...this.element.querySelectorAll(".designer__preset")].find(button => {
      const axes = JSON.parse(button.dataset.designerAxesParam)
      return Object.entries(axes).every(([key, value]) => this.design[key] === value)
    })
    this.presetTarget.textContent = match ? (match.dataset.label || match.textContent.trim()) : "Custom"
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

  // The working design, as the preview build and the save both post it.
  payload() {
    return { design: this.design, nav: this.nav, fonts: this.fonts, colors: this.colors,
      hero: this.hero, newsletter: this.newsletter, footer: this.footer, sections: this.sections }
  }

  async build() {
    this.building = true
    this.statusTarget.textContent = "Building preview…"
    const response = await fetch(this.buildUrlValue, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf },
      body: JSON.stringify(this.payload())
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
