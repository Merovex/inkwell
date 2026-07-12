class Ahoy::Store < Ahoy::DatabaseStore
  # Coarse geography only: keep country/region from the geocode result, drop
  # city/postal/lat-lng, and discard the (already masked) IP once it has served
  # its purpose. Net effect: we store LESS identifying data than before
  # geocoding, plus a location no finer than "state". (Geocoding itself is
  # enabled in the geocoder initializer, which loads after this one.)
  def geocode(data)
    super(data.slice(:visit_token, :country, :region))
    visit&.update_columns(ip: nil)
  end
end

# JavaScript tracking: the public site is edge-cached, so visits are created
# client-side (ahoy.js) — server-side visits are off to avoid setting a
# per-visitor cookie on cacheable responses. See app/javascript/public.js.
Ahoy.api = true
Ahoy.server_side_visits = false

# Mask the last IP octet before storing/geocoding — resolves to country/state
# reliably, never to a household.
Ahoy.mask_ips = true
