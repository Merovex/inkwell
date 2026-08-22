class Ahoy::Store < Ahoy::DatabaseStore
  # Visits carry the tenant whose public site they landed on (nil for app-host
  # traffic) — per-account scoping (ADR 0017). The analytics dashboard that
  # read these is gone; the weekly digest's per-post reads still uses them.
  #
  # The IP is dropped before the visit is written. Geocoding used to be the
  # thing that discarded it (once it had yielded a country), so with geography
  # gone the IP has no remaining purpose — and never storing it is a stronger
  # guarantee than storing-then-clearing ever was.
  def track_visit(data)
    data[:account_id] = Current.account&.id
    data[:ip] = nil
    super
  end
end

# JavaScript tracking: the public site is edge-cached, so visits are created
# client-side (ahoy.js) — server-side visits are off to avoid setting a
# per-visitor cookie on cacheable responses. See app/javascript/public.js.
Ahoy.api = true
Ahoy.server_side_visits = false
