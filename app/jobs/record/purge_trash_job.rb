# Incinerates trash past its purge deadline (records.purge_after — 30 days
# normally, 2 years for ever-published content). Runs on the recurring
# schedule (config/recurring.yml); destroy cascades versions, bodies, and
# rich text/attachments.
class Record::PurgeTrashJob < ApplicationJob
  def perform
    # A deliberate cross-account sweep: the purge deadline decides, not tenancy.
    Current.allowing_unscoped_tenancy { Record.purgeable.find_each(&:destroy) }
  end
end
