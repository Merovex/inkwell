require "csv"

# The subscriber roster — domain-admin only. Read + export + honor-an-unsubscribe;
# there's no create/edit here, since subscribers opt in from the public site. The
# CSV export is the bridge to an external sender until one is wired (ADR 0011).
class Admin::SubscribersController < Admin::BaseController
  # The roster is one state at a time; the header links between them.
  STATES = %w[ confirmed pending unsubscribed bounced ].freeze

  before_action :set_subscriber, only: %i[ unsubscribe resend ]

  def index
    @state = STATES.include?(params[:state]) ? params[:state] : "confirmed"
    @subscribers = Current.account.subscribers.where(status: @state).order(created_at: :desc)
    @counts = Current.account.subscribers.group(:status).count

    respond_to do |format|
      format.html
      format.csv { send_data subscribers_csv, filename: "subscribers-#{@state}-#{Date.current.iso8601}.csv" }
    end
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
        csv << %w[ email_address status source confirmed_at unsubscribed_at created_at ]
        @subscribers.each do |s|
          csv << [ s.email_address, s.status, s.source, s.confirmed_at, s.unsubscribed_at, s.created_at ]
        end
      end
    end
end
