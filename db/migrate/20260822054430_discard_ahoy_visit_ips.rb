# Geocoding was what discarded a visit's (already masked) IP once it had
# yielded a country. With geography gone the store never writes an IP at all,
# which leaves historical rows as the only place one survives — for no reader.
# Clear them. One-way by design: an IP we chose to stop keeping shouldn't come
# back on a rollback.
class DiscardAhoyVisitIps < ActiveRecord::Migration[8.2]
  def up
    Ahoy::Visit.where.not(ip: nil).in_batches.update_all(ip: nil)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
