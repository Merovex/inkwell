# A one-time email send of a post to confirmed subscribers (HEY World: a
# published post can also go out as the newsletter). Lives on the post's Record
# — the stable identity — so it's independent of the post's versions, and the
# unique index on record_id means a post can be broadcast exactly once. Creating
# the row is the guard; PostBroadcastJob then fans out and stamps the outcome.
class Broadcast < ApplicationRecord
  belongs_to :record
  has_many :deliveries, class_name: "BroadcastDelivery", dependent: :destroy

  validates :record_id, uniqueness: true

  # The post being sent (the record's current version).
  def post
    record.recordable
  end

  def sent?
    sent_at.present?
  end

  # Booked to send later and not yet sent — the wait_until job is pending.
  def scheduled?
    scheduled_at.present? && !sent?
  end
end
