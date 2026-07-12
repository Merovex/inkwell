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

  # Close the run (unsubscribed / completed). Idempotent.
  def end!(reason)
    update!(ended_at: Time.current, ended_reason: reason) unless ended_at
  end
end
