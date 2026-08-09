require "csv"

# The broadcasts dashboard: every post that's been emailed (or is scheduled to
# be), with how each one landed. Domain-admin only. Read-only — sending is
# driven from the post page (Admin::Posts::BroadcastsController).
#
# index is facts-first: the 30-day totals over a per-send table. show is one
# send's detail — who got it, who bounced, and who clicked. Everything reads the
# canonical delivery milestones (ADR 0025) — no ESP dashboard needed.
class Admin::BroadcastsController < Admin::BaseController
  def index
    @broadcasts = Current.account.broadcasts.includes(:record).order(created_at: :desc)

    # 30-day totals — the facts that lead the page. Clicks are the trustworthy
    # engagement signal; opens are under-counted (blocked tracking pixels).
    window = 30.days.ago.beginning_of_day
    deliveries = BroadcastDelivery.where(broadcast_id: Current.account.broadcasts.select(:id))
    @sent_30d      = deliveries.where(sent_at: window..).count
    @delivered_30d = deliveries.where(delivered_at: window..).count
    @clicked_30d   = deliveries.where(clicked_at: window..).count
    @trouble_30d   = deliveries.where(bounced_at: window..).count +
                     deliveries.where(complained_at: window..).count +
                     deliveries.where(unsubscribed_at: window..).count

    # Hard-bounce addresses per broadcast, for the amber note under a row.
    @bounced_addresses = BroadcastDelivery.where(broadcast_id: @broadcasts.map(&:id))
      .where.not(bounced_at: nil).includes(:subscriber)
      .group_by(&:broadcast_id)
      .transform_values { |ds| ds.map { |d| d.subscriber.email_address } }

    respond_to do |format|
      format.html
      format.csv { send_data broadcasts_csv, filename: "broadcasts-#{Date.current.iso8601}.csv" }
    end
  end

  def show
    @broadcast = Current.account.broadcasts.includes(:record).find(params[:id])
    @deliveries = @broadcast.deliveries.includes(:subscriber).order(:sent_at, :id)
    @bounced = @deliveries.select(&:bounced_at)
    @unclicked = @deliveries.count { |d| d.delivered_at && !d.clicked_at && !d.bounced_at }
  end

  private
    def broadcasts_csv
      CSV.generate do |csv|
        csv << %w[ post sent_at recipients delivered opened clicked bounced complained unsubscribed ]
        @broadcasts.each do |b|
          csv << [ b.post&.title, b.sent_at, b.recipients_count, b.delivered_count,
                   b.opened_count, b.clicked_count, b.bounced_count, b.complained_count, b.unsubscribed_count ]
        end
      end
    end
end
