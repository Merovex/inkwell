# One row per (stream, drop): whether a Drop was sent to a subscriber or skipped,
# plus SES engagement milestones. Mirrors BroadcastDelivery — the unique
# [stream, drop] index makes the send tick idempotent, and record_event! stamps
# SES events arriving through Webhooks::SesController. Metrics are computed from
# these rows (no cached counters) — fine at newsletter scale.
class DropDelivery < ApplicationRecord
  belongs_to :stream
  belongs_to :drop_record, class_name: "Record"
  belongs_to :subscriber

  # pending → not yet due; sent → mailed; skipped → subscriber ineligible at
  # send time (unsubscribed), recorded (with skip_reason) but never mailed.
  enum :status, %w[ pending sent skipped ].index_by(&:itself), default: "pending", prefix: true

  # Opens and clicks are engagement — they reset the subscriber's sunset clock.
  ENGAGEMENT = %w[ opened clicked ].freeze

  # SES event name → the milestone column it stamps (first-event-wins).
  EVENTS = {
    "delivered"    => :delivered_at,
    "opened"       => :opened_at,
    "clicked"      => :clicked_at,
    "bounced"      => :bounced_at,
    "complained"   => :complained_at,
    "unsubscribed" => :unsubscribed_at
  }.freeze

  def drop = drop_record.recordable

  # Record an SES engagement event once. Stamps the milestone and, for
  # opens/clicks, keeps the subscriber's engagement clock warm. No-op on repeats.
  def record_event!(event)
    column = EVENTS[event]
    return false unless column
    return false if self[column]

    transaction do
      update!(column => Time.current)
      subscriber.mark_engaged! if ENGAGEMENT.include?(event)
    end
    true
  end
end
