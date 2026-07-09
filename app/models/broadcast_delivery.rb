# One subscriber's copy of a broadcast: created when the fan-out reaches them,
# stamped sent_at once the email is handed off. The (broadcast, subscriber)
# unique index makes re-runs safe. created_at only — a delivery isn't edited
# beyond its single sent_at stamp.
class BroadcastDelivery < ApplicationRecord
  belongs_to :broadcast
  belongs_to :subscriber
end
