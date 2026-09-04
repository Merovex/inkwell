require "csv"

# The subscriber roster — domain-admin only. Read + export + honor-an-unsubscribe;
# there's no create/edit here, since subscribers opt in from the public site. The
# CSV export is the bridge to an external sender until one is wired (ADR 0011).
class Admin::SubscribersController < Admin::BaseController
  # The roster is one state at a time; the header links between them.
  STATES = %w[ confirmed pending unsubscribed bounced complained ].freeze

  before_action :set_subscriber, only: %i[ show unsubscribe resend ]

  def index
    @state = STATES.include?(params[:state]) ? params[:state] : "confirmed"
    @subscribers = Current.account.subscribers.where(status: @state).order(created_at: :desc)
    # The site's magnets feed the per-magnet "Send … link" row actions — every
    # confirmed reader is sendable, grant or no grant (create mints one).
    @magnets = Current.account.magnets.ordered
    # Seeds stay visible in the roster (badged) but out of the headline counts —
    # they're diagnostics, not readers.
    @counts = Current.account.subscribers.readers.group(:status).count

    respond_to do |format|
      format.html
      format.csv { send_data subscribers_csv, filename: "subscribers-#{@state}-#{Date.current.iso8601}.csv" }
    end
  end

  # One subscriber's detail — opened into the roster's modal frame: their
  # lifecycle dates and what they've received/opened, newest send first.
  def show
    @deliveries = @subscriber.broadcast_deliveries
      .includes(broadcast: { record: :recordable }).order(created_at: :desc)
    @received = @deliveries.count
    @opened = @deliveries.count { |d| d.opened_at.present? }
    @last_opened_at = @deliveries.filter_map(&:opened_at).max
    # Every site magnet is offerable; the grant (when one exists) dates the row.
    @magnets = Current.account.magnets.ordered
    @grants_by_magnet = @subscriber.grants.index_by(&:magnet_id)
    # Which campaigns they're in and where each run has got to — the answer to
    # "why did this reader get that email?", newest enrollment first.
    @streams = @subscriber.streams.includes(:deliveries, drip_record: :recordable)
      .order(enrolled_at: :desc)
  end

  # Manual opt-out on someone's behalf (a reply-to-email request, say). Same
  # path as a token unsubscribe — flips status and appends the consent event.
  def unsubscribe
    @subscriber.unsubscribe!(ip: request.remote_ip, source: "admin")
    redirect_to admin_subscribers_path, notice: "#{@subscriber.email_address} unsubscribed."
  end

  # Re-issue the double opt-in email to a still-pending subscriber — a fresh
  # tokened confirm link (the original expires after 7 days). Useful for
  # re-inviting people who signed up under the old sender identity. Only pending
  # rows have anything to confirm, so anything else is a no-op with a heads-up.
  def resend
    if @subscriber.pending?
      @subscriber.send_confirmation
      redirect_to admin_subscribers_path(state: "pending"),
        notice: "Confirmation email re-sent to #{@subscriber.email_address}."
    else
      redirect_to admin_subscribers_path(state: @subscriber.status),
        alert: "#{@subscriber.email_address} isn't pending — nothing to confirm."
    end
  end

  private
    def set_subscriber
      @subscriber = Current.account.subscribers.find(params[:id])
    end

    def subscribers_csv
      CSV.generate do |csv|
        csv << %w[ email_address status source seed confirmed_at unsubscribed_at created_at ]
        @subscribers.each do |s|
          csv << [ s.email_address, s.status, s.source, s.seed, s.confirmed_at, s.unsubscribed_at, s.created_at ]
        end
      end
    end
end
