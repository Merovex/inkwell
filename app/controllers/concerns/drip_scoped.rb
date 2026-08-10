# Resolves the Drip's Record (the public identity — /admin/drips/:id is a Record
# id) and its current version, for the drip controllers and the nested drops
# controller (which passes the drip as :drip_id).
module DripScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Current.account.records.active.drips.find(params[:drip_id] || params[:id])
      @drip = @record.recordable
    end

    # ── Read-only campaign/step aggregates for the re-skinned admin ─────────
    # All reads over the existing Stream/DropDelivery rows; nothing here writes
    # or changes behavior. N+1 by campaign/step — fine at newsletter scale, the
    # same trade the dashboard's upcoming_sends already makes.

    # in-it-now / finished / left-partway (ended for any other reason) and how
    # many enrollees clicked at least one step.
    def campaign_stats(drip_record_id)
      streams = Stream.where(drip_record_id: drip_record_id)
      clicked = DropDelivery.where(stream_id: streams.select(:id)).where.not(clicked_at: nil)
      {
        in_now:   streams.active.count,
        finished: streams.where(ended_reason: "completed").count,
        left:     streams.where.not(ended_at: nil).where.not(ended_reason: "completed").count,
        clicked:  clicked.distinct.count(:stream_id)
      }
    end

    # sent / clicked / unsubscribed counts for one step (Drop record).
    def step_stats(drop_record_id)
      deliveries = DropDelivery.where(drop_record_id: drop_record_id)
      {
        sent:    deliveries.status_sent.count,
        clicked: deliveries.where.not(clicked_at: nil).count,
        unsub:   deliveries.where.not(unsubscribed_at: nil).count
      }
    end
end
