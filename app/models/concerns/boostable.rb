# Mix into Record to let people pin boosts to it — tiny Basecamp-style
# appreciations (short text or emoji), several per person allowed. Boosts
# live off the version spine on purpose: boosting never revises the record
# and never lands in its events feed.
module Boostable
  extend ActiveSupport::Concern

  included do
    # Creation order is display order. Off-spine metadata, not content:
    # nothing to instantiate on teardown, so delete_all.
    has_many :boosts, -> { order(:id) }, dependent: :delete_all
  end
end
