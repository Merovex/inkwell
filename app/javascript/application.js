// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Register the service worker so the app is an installable PWA (dev-as-PWA, ADR 0005).
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker").catch(() => {})
}

// Rich text editor for Action Text bodies (replaces Trix; speaks the same protocol).
// Cap headings at H2 so bodies never emit an <h1> — the page title owns that level.
// configure() must run synchronously right after the import (editors register once
// the import's call stack completes).
import * as Lexxy from "lexxy"
Lexxy.configure({ default: { headings: ["h2", "h3", "h4"] } })

// Charts for the drip dashboard (Chart.js via chartkick).
import "chartkick"
import "Chart.bundle"
