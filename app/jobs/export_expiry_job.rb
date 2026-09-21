# Daily sweep that destroys site exports past Export::RETENTION — the record,
# its row, and the zip with it. An export holds the subscriber list, so an old
# one is a liability, not a keepsake; the author can always ask for a fresh
# one. Idempotent. A deliberate cross-account sweep: age, not tenancy, decides.
class ExportExpiryJob < ApplicationJob
  def perform
    Current.allowing_unscoped_tenancy do
      Export.expired.includes(:record).find_each { |export| export.record.destroy }
    end
  end
end
