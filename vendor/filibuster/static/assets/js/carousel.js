// Drag-to-scroll for the carousel book band (data-cards="carousel") — the
// theme's one reader-side script, shipped ONLY when carousel is the chosen
// layout. Dependency-free pointer capture: mouse drag pans the band (touch
// and trackpad already pan natively), snap suspends while held and
// re-engages on release, and a real drag suppresses the card's link click.
for (const list of document.querySelectorAll(".fk-series-list")) {
  let startX = 0, startLeft = 0, dragging = false, moved = false

  list.addEventListener("pointerdown", event => {
    if (event.pointerType !== "mouse") return
    // Without this, dragging a card (an <a> full of <img>) starts the
    // browser's NATIVE drag operation, which pointercancels our stream.
    event.preventDefault()
    dragging = true
    moved = false
    startX = event.clientX
    startLeft = list.scrollLeft
    list.classList.add("is-dragging")
    list.setPointerCapture(event.pointerId)
  })

  // Belt and suspenders: kill HTML5 drag on links/images inside the band.
  list.addEventListener("dragstart", event => event.preventDefault())

  list.addEventListener("pointermove", event => {
    if (!dragging) return
    const delta = event.clientX - startX
    if (Math.abs(delta) > 5) moved = true
    list.scrollLeft = startLeft - delta
  })

  const release = () => {
    dragging = false
    list.classList.remove("is-dragging")
  }
  list.addEventListener("pointerup", release)
  list.addEventListener("pointercancel", release)

  // A drag is not a click: swallow the navigation the stretched card link
  // would otherwise perform on release.
  list.addEventListener("click", event => {
    if (moved) {
      event.preventDefault()
      event.stopPropagation()
      moved = false
    }
  }, true)
}
