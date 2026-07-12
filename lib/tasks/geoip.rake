# Visit-geography maintenance. Requires an MMDB city database in
# storage/geoip/ (download instructions in config/initializers/geocoder.rb).
namespace :geoip do
  desc "Geocode existing visits that still have a stored (masked) IP, then discard the IP"
  task backfill: :environment do
    abort "Geo database missing — see config/initializers/geocoder.rb" if GEOIP_DATABASE.nil?

    scope = Ahoy::Visit.where(country: nil).where.not(ip: nil)
    total = scope.count
    done = 0
    scope.find_each do |visit|
      location = Geocoder.search(visit.ip).first
      updates = { ip: nil } # spent — discard either way, matching the live flow
      if location&.country.present?
        updates[:country] = location.country
        updates[:country_code] = location.try(:country_code).presence
        updates[:region] = location.try(:state).presence
      end
      visit.update_columns(updates)
      done += 1
      puts "#{done}/#{total}" if (done % 500).zero?
    end
    puts "Backfilled #{done} visits (of #{total} with a stored IP)."
  end
end
