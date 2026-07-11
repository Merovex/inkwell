# Namespace the session + auth cookies per deployment so two sites running this
# same codebase don't clobber each other's login. Cookies are scoped by domain
# and ignore port, so without this, `localhost:3000` and `localhost:3001` (dev),
# or two subdomains of one apex (prod), share one `_inkwell_session` /
# `session_id` cookie — logging into one signs you out of the other.
#
# Each site sets APP_NAMESPACE (e.g. `press`, `blog`) to get its own cookies.
# Falls back to the app name so a lone deployment needs no config.
Rails.application.config.x.cookie_namespace =
  ENV.fetch("APP_NAMESPACE") { Rails.application.class.module_parent_name.underscore }

Rails.application.config.session_store :cookie_store,
  key: "_#{Rails.application.config.x.cookie_namespace}_session"
