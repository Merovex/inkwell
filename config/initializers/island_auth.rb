# The shared secrets the edge Worker presents on proxied island requests
# (IslandProtected). An array so a current and a next secret can overlap
# during rotation. Empty = check disabled. Mirrored config.x-style — same
# pattern as config.x.app_host — so tests can swap it directly.
#
# Deliberately EMPTY in test: the credentials file is shared across
# environments, so once ops provisions the real secret the suite would
# otherwise boot with island auth enforced and 403 every anonymous request.
# Tests opt in per-case via config.x.
Rails.application.config.x.island_auth_secrets =
  Rails.env.test? ? [] : Array(Rails.application.credentials.island_auth_secrets)
