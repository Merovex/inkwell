# A tiny burst of appreciation pinned to a record (a post or comment today,
# a chat line whenever Chat lands) — short text or emoji, Basecamp style.
# Deliberately off the version spine: no history, no events-feed entry, no
# trash ceremony. Created and deleted outright; several per person allowed.
class Boost < ApplicationRecord
  MAX_LENGTH = 16
  # The quick picks in the palette popover; free text covers everything else.
  # All-positive by design (disagreement belongs in a comment) — 🤔 is the
  # closest thing to dissent: "made me think", politely.
  COMMON_EMOJIS = %w[ 👍 ❤️ 🎉 😂 😮 🙏 🔥 💯 😢 👏 👀 🤔 ]

  belongs_to :record
  belongs_to :creator, class_name: "User", default: -> { Current.user }
  # The author's "boosted your…" bell row keeps its stamped copy if the
  # boost is taken back.
  has_many :notifications, as: :source, dependent: :nullify

  validates :content, presence: true, length: { maximum: MAX_LENGTH }

  # Live wall: a boost lands on (or leaves) every open Wall for this circle —
  # the card's chip strip updates in place (circles/walls subscribe via
  # turbo_stream_from). Circle buckets only; account-side boosts have no wall.
  # The chip renders read-only (removable: false), so no Current leaks into
  # the background render.
  after_create_commit :broadcast_to_wall
  after_destroy_commit :broadcast_removal_from_wall

  private
    def broadcast_to_wall
      return unless record.bucket_type == "Circle"
      broadcast_append_later_to [ record.bucket, :wall ],
        target: ActionView::RecordIdentifier.dom_id(record, :wall_boosts),
        partial: "circles/walls/boost_chip", locals: { boost: self }
    end

    def broadcast_removal_from_wall
      return unless record.bucket_type == "Circle"
      broadcast_remove_to [ record.bucket, :wall ],
        target: ActionView::RecordIdentifier.dom_id(self, :wall)
    end
end
