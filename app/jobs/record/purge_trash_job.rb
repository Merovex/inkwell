# Incinerates trash past its purge deadline (records.purge_after — 30 days
# normally, 2 years for ever-published content). Runs on the recurring
# schedule (config/recurring.yml); destroy cascades versions, bodies, and
# rich text/attachments.
class Record::PurgeTrashJob < ApplicationJob
  def perform
    # A deliberate cross-account sweep: the purge deadline decides, not tenancy.
    Current.allowing_unscoped_tenancy { Record.purgeable.find_each { |record| purge record } }
  end

  private
    # One record's failure is its own. The sweep used to destroy straight out of
    # find_each with nothing to catch it, so the first record that raised — a
    # table hanging off the Record spine with no cleanup declared, tripping its
    # foreign key — aborted the whole night's purge and left every record behind
    # it sitting in trash, across every account. Report and carry on: the record
    # is still purgeable tomorrow, so the sweep retries it once the gap is
    # closed. Nothing is swallowed — each failure is its own Honeybadger fault,
    # named by the record it belongs to.
    def purge(record)
      record.destroy
    rescue StandardError => e
      Honeybadger.notify(e, context: { record_id: record.id,
                                       recordable_type: record.recordable_type,
                                       bucket: "#{record.bucket_type}##{record.bucket_id}" })
    end
end
