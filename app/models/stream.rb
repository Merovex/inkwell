# One subscriber's run through a Drip (their "enrollment"). enrolled_at — the
# subscriber's confirmation time — anchors every Drop's send. A Stream ends when
# the subscriber unsubscribes or finishes the sequence; it is never re-run
# (unique per subscriber + drip). drip_record_id points at the Drip's stable
# Record, so the run survives edits to the campaign.
class Stream < ApplicationRecord
  belongs_to :subscriber
  belongs_to :drip_record, class_name: "Record"
  has_many :deliveries, class_name: "DropDelivery", dependent: :destroy

  # Uniqueness is enforced by the DB index (unique [subscriber_id, drip_record_id]),
  # which lets Drip#enroll use create_or_find_by! to be idempotent on re-confirm —
  # a model validation would raise before the index could catch the race.
  scope :active, -> { where(ended_at: nil) }

  def drip = drip_record.recordable

  # Send every Drop now due to this subscriber, or record a skip if they've
  # become ineligible (unsubscribed) by the time it comes due. Idempotent: a
  # delivery already sent/skipped is left alone, so re-running the tick — or a
  # retried job — never re-mails. Drops come due in position order.
  def advance!(now: Time.current)
    return if ended_at

    due_drops(now:).each do |drop|
      delivery = deliveries.create_or_find_by!(drop_record: drop.record) { |d| d.subscriber = subscriber }
      next unless delivery.status_pending?

      if subscriber.confirmed?
        DropMailer.step(self, drop).deliver_now
        delivery.update!(status: :sent, sent_at: Time.current)
      else
        delivery.update!(status: :skipped, skip_reason: subscriber.status)
      end
    end
  end

  # Drops whose scheduled day has arrived (enrolled_at + delay_days ≤ now) and
  # that haven't been recorded yet, in send order.
  def due_drops(now: Time.current)
    recorded = deliveries.pluck(:drop_record_id)
    drip.drops.reject { |drop| recorded.include?(drop.record_id) || drop.send_at_for(self) > now }
  end

  # Close the run (unsubscribed / completed). Idempotent.
  def end!(reason)
    update!(ended_at: Time.current, ended_reason: reason) unless ended_at
  end
end
