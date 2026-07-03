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

  validates :content, presence: true, length: { maximum: MAX_LENGTH }
end
