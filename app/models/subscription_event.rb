# One immutable entry in a subscriber's consent log: a state transition stamped
# with when, from where, and the IP. This is the legal proof-of-consent trail —
# events are appended, never edited or reordered. See ADR 0011.
class SubscriptionEvent < ApplicationRecord
  ACTIONS = %w[ subscribed confirmed unsubscribed resubscribed ].freeze

  belongs_to :subscriber

  validates :action, inclusion: { in: ACTIONS }

  # Append-only: an event is a historical fact. Creating is allowed; changing a
  # persisted one is not.
  before_update { raise ActiveRecord::ReadOnlyRecord, "subscription events are append-only" }
end
