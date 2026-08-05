# The broadcasts dashboard: every post that's been emailed (or is scheduled to
# be), with its newsletter metrics. Domain-admin only. Read-only — sending is
# driven from the post page (Admin::Posts::BroadcastsController).
#
# index carries the account-wide overview (the range's daily sent/opened/bounced
# series + totals) above the per-post table; show is one send's detail:
# per-recipient milestones and the link-click breakdown. Everything reads the
# canonical DeliveryEvent substrate (ADR 0025) — no ESP dashboard needed.
class Admin::BroadcastsController < Admin::BaseController
  # Selectable windows for the overview. 30d today; the rest light up as the
  # account accrues history (docs/email-architecture.md).
  RANGES = { "30d" => 30 }.freeze

  def index
    @broadcasts = Current.account.broadcasts.includes(:record).order(created_at: :desc)

    @range = RANGES.key?(params[:range]) ? params[:range] : "30d"
    window = RANGES[@range].days.ago.beginning_of_day

    deliveries = BroadcastDelivery.where(broadcast_id: Current.account.broadcasts.select(:id))
    events = DeliveryEvent.where(delivery_type: "BroadcastDelivery", delivery_id: deliveries.select(:id))
                          .where(occurred_at: window..)

    # Daily series for the chart: handed to the client as JSON; the area-chart
    # controller draws the SVG (client-rendered on purpose — theme-aware via
    # CSS classes, no chart library).
    sent_by_day    = deliveries.where(sent_at: window..).group("date(sent_at)").count
    opened_by_day  = events.opened.group("date(occurred_at)").count
    bounced_by_day = events.hard_bounce.group("date(occurred_at)").count

    days = (window.to_date..Date.current).to_a
    @chart = {
      labels: days.map { |d| d.strftime("%b %-d") },
      series: [
        { name: "Sent",    key: "sent",    values: days.map { |d| sent_by_day[d.iso8601].to_i } },
        { name: "Opened",  key: "opened",  values: days.map { |d| opened_by_day[d.iso8601].to_i } },
        { name: "Bounced", key: "bounced", values: days.map { |d| bounced_by_day[d.iso8601].to_i } }
      ]
    }

    # The totals sentence + breakdown chips under the chart.
    @window_sent       = deliveries.where(sent_at: window..).count
    @window_opened     = events.opened.distinct.count(:delivery_id)
    @window_hard       = events.hard_bounce.count
    @window_soft       = events.soft_bounce.count
    @window_complaints = events.complaint.count
  end

  def show
    @broadcast = Current.account.broadcasts.includes(:record).find(params[:id])
    @deliveries = @broadcast.deliveries.includes(:subscriber).order(:sent_at, :id)

    # Which links got clicked: SES stamps the URL on each click event
    # (payload.click.link); Postmark called it OriginalLink. Tallied in Ruby —
    # a broadcast's click volume is small.
    @link_clicks = DeliveryEvent.clicked
      .where(delivery_type: "BroadcastDelivery", delivery_id: @broadcast.deliveries.select(:id))
      .filter_map { |e| e.payload.dig("click", "link") || e.payload["OriginalLink"] }
      .tally.sort_by { |_url, count| -count }
  end
end
