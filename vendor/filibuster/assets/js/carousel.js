// Drag-to-scroll for the carousel book band (data-cards="carousel") — the
// theme's one reader-side script, shipped ONLY when carousel is the chosen
// layout. Dependency-free pointer panning: a mouse DRAG pans the band, while a
// plain CLICK still follows the cover's link.
//
// The subtlety that bit us: capturing the pointer and preventDefault-ing on
// pointerdown swallows the click on the stretched <a> cover links (the card
// never navigates, only "open in new tab" works). So we ARM on pointerdown but
// only COMMIT to a drag once the pointer moves past a threshold — capturing and
// suppressing default then. A click that never moves is left completely alone.
for (const list of document.querySelectorAll(".fk-series-list")) {
  let startX = 0, startLeft = 0, pointerId = null, dragging = false, moved = false

  list.addEventListener("pointerdown", event => {
    if (event.pointerType !== "mouse") return
    // Arm only — no preventDefault, no capture yet, so the click survives.
    pointerId = event.pointerId
    dragging = false
    moved = false
    startX = event.clientX
    startLeft = list.scrollLeft
  })

  list.addEventListener("pointermove", event => {
    if (pointerId === null || event.pointerId !== pointerId) return
    const delta = event.clientX - startX
    if (!dragging) {
      if (Math.abs(delta) <= 5) return  // still within click tolerance
      // Past the threshold: this is a real drag. Now capture and suppress the
      // native drag/selection, and mark the gesture so the click is swallowed.
      dragging = true
      moved = true
      list.classList.add("is-dragging")
      list.setPointerCapture(pointerId)
    }
    event.preventDefault()
    list.scrollLeft = startLeft - delta
  })

  const release = () => {
    pointerId = null
    dragging = false
    list.classList.remove("is-dragging")  // pointer capture auto-releases on up
  }
  list.addEventListener("pointerup", release)
  list.addEventListener("pointercancel", release)

  // Belt and suspenders: kill HTML5 image/link drag inside the band.
  list.addEventListener("dragstart", event => event.preventDefault())

  // A real drag is not a click: swallow the navigation the stretched card link
  // would otherwise perform on release. A plain click leaves moved false.
  list.addEventListener("click", event => {
    if (moved) {
      event.preventDefault()
      event.stopPropagation()
      moved = false
    }
  }, true)
}
