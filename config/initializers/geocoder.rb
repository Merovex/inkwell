# Offline IP→geo lookups for Ahoy visit geography. An MMDB city database
# (memory-mapped) lives OUTSIDE git in storage/geoip/ — either source works,
# first match wins:
#
#   GeoLite2-City.mmdb   — MaxMind GeoLite2 (~60 MB); free account required:
#     curl -Lo /tmp/geoip.tgz "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=YOUR_KEY&suffix=tar.gz"
#     tar -xzf /tmp/geoip.tgz --strip-components=1 -C storage/geoip --wildcards "*/GeoLite2-City.mmdb"
#
#   dbip-city-lite.mmdb  — DB-IP City Lite (~130 MB); no account (CC BY 4.0),
#     slightly coarser region accuracy. Monthly file:
#     curl -sL "https://download.db-ip.com/free/dbip-city-lite-YYYY-MM.mmdb.gz" | gunzip > storage/geoip/dbip-city-lite.mmdb
#
# Refresh monthly-ish. No lookup ever leaves the server; without a file,
# geocoding stays disabled entirely rather than falling back to a web API.
# The Ahoy store slices results down to country/region and discards the IP
# (see the ahoy initializer).
GEOIP_DATABASE = %w[GeoLite2-City.mmdb dbip-city-lite.mmdb]
  .map { |name| Rails.root.join("storage/geoip", name) }
  .find(&:exist?)

if GEOIP_DATABASE
  Geocoder.configure(
    ip_lookup: :geoip2,
    geoip2: { file: GEOIP_DATABASE.to_s }
  )
  Ahoy.geocode = true
end
