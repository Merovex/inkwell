# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "lexxy", to: "lexxy.min.js"
# Lexxy uses Active Storage direct uploads for images; it imports this module.
pin "@rails/activestorage", to: "activestorage.esm.js"
# First-party analytics on the public site (client-side, so it survives edge
# caching). Loaded via the lightweight "public" entry point, not the admin bundle.
pin "ahoy", to: "ahoy.js"
pin "public"
# Visitor-geography choropleth on the admin analytics page (UMD globals —
# imported for side effect; use window.jsVectorMap).
pin "jsvectormap"
pin "jsvectormap-world"
pin "jsvectormap-us"
