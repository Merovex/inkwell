# The shared secrets the edge Worker presents on proxied island requests
# (IslandProtected). An array so a current and a next secret can overlap
# during rotation. Empty (dev, test, pre-cutover production) disables the
# check. Mirrored config.x-style so tests can swap it without decrypting
# credentials — same pattern as config.x.app_host.
Rails.application.config.x.island_auth_secrets =
  Array(Rails.application.credentials.island_auth_secrets)
