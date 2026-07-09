class Ahoy::Store < Ahoy::DatabaseStore
end

# JavaScript tracking: the public site is edge-cached, so visits are created
# client-side (ahoy.js) — server-side visits are off to avoid setting a
# per-visitor cookie on cacheable responses. See app/javascript/public.js.
Ahoy.api = true
Ahoy.server_side_visits = false

# Mask the last IP octet — we don't geocode, and it's friendlier for privacy.
Ahoy.mask_ips = true
