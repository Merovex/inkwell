# A drip campaign: an ordered sequence of Drops mailed to a subscriber on a
# schedule anchored to a trigger (subscriber confirmation, for now). A recordable
# — its rows are the versions of a Record — so edits and activate/deactivate land
# as tracked history. Streams (per-subscriber runs) and Drops (the emails) hang
# off the stable Record identity, so they survive edits to the campaign.
class Drip < ApplicationRecord
  include Recordable

  TRIGGERS = %w[ confirmed ].freeze

  has_many :streams, primary_key: :record_id, foreign_key: :drip_record_id, dependent: :destroy

  validates :title, presence: true
  validates :trigger, inclusion: { in: TRIGGERS }

  # Current versions of live (non-trashed) drips; `live` narrows to the active
  # ones eligible to enroll new subscribers.
  scope :current, -> { where(id: Record.active.where(recordable_type: "Drip").select(:recordable_id)) }
  scope :live,    -> { current.where(active: true) }

  # Every version is history — activating/deactivating lands as a new version,
  # so we never amend in place (see Comment for the same choice).
  def mutable? = false

  # The Drop emails in this campaign: current versions of the child Records
  # (parent = this Drip's Record), ordered by their Record.position.
  def drops
    Drop.where(id: Record.active.where(recordable_type: "Drop", parent_id: record_id).select(:recordable_id))
      .joins(:record).order("records.position")
  end

  # Enroll a newly-confirmed subscriber into every active drip. Called from
  # Subscriber#confirm!.
  def self.enroll(subscriber)
    live.find_each { |drip| drip.enroll(subscriber) }
  end

  # Start (or find) this subscriber's Stream, anchored at their confirmation
  # time. Idempotent — the unique (subscriber, drip) index guards re-confirms.
  def enroll(subscriber)
    streams.create_or_find_by!(subscriber: subscriber) do |stream|
      stream.enrolled_at = subscriber.confirmed_at || Time.current
    end
  end
end
