require "csv"

# The subscriber list as three CSVs, split so the file an author imports into
# their next sender can't mail anyone who shouldn't be mailed:
#
#   subscribers.csv     — confirmed readers who may be emailed. Nobody else.
#   suppressions.csv    — do-not-mail: unsubscribed, bounced, complained, or
#                         suppressed. Every sender takes this as its own import.
#   consent_events.csv  — the append-only consent log (when, how, from where):
#                         the proof of opt-in that travels with the list.
#
# Pending (never confirmed) addresses and deliverability seeds are in neither
# list: the first never consented, the second aren't readers.
class Export::Roster
  def initialize(account)
    @account = account
  end

  def files
    { "subscribers.csv" => subscribers_csv,
      "suppressions.csv" => suppressions_csv,
      "consent_events.csv" => consent_events_csv }
  end

  private
    attr_reader :account

    def subscribers_csv
      csv %w[ email_address confirmed_at source source_url country_code created_at ],
        mailable.order(:email_address)
          .pluck(:email_address, :confirmed_at, :source, :source_url, :country_code, :created_at)
    end

    def suppressions_csv
      rows = unmailable.order(:email_address).pluck(:email_address, :status, :unsubscribed_at, :updated_at)
        .map do |email, status, unsubscribed_at, updated_at|
          # Still "confirmed" here means the platform suppression is what stops mail.
          [ email, status == "confirmed" ? "suppressed" : status, unsubscribed_at || updated_at ]
        end
      csv %w[ email_address reason since ], rows
    end

    def consent_events_csv
      csv %w[ email_address action source ip_address happened_at ],
        SubscriptionEvent.for_account(account).merge(Subscriber.readers)
          .order("subscription_events.created_at", "subscription_events.id")
          .pluck("subscribers.email_address", :action, "subscription_events.source",
            :ip_address, "subscription_events.created_at")
    end

    def mailable
      account.subscribers.sendable.where.not(person_id: suppressed_people)
    end

    def unmailable
      readers = account.subscribers.readers
      readers.where(status: %w[ unsubscribed bounced complained ])
        .or(readers.confirmed.where(person_id: suppressed_people))
    end

    def suppressed_people = Suppression.in_force_for(account).select(:person_id)

    # One unambiguous clock for every sender's importer: ISO 8601, UTC.
    def timestamp(value) = value.respond_to?(:utc) ? value.utc.iso8601 : value

    def csv(header, rows)
      CSV.generate do |out|
        out << header
        rows.each { |row| out << SpreadsheetSafe.row(row.map { |value| timestamp(value) }) }
      end
    end
end
