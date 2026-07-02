// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Register the service worker so the app is an installable PWA (dev-as-PWA, ADR 0005).
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker").catch(() => {})
}
