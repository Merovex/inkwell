# A message-board category, Basecamp style: an emoji icon and a name, worn
# in the message's byline ("📢 Announcement by Ben Wilson"). A plain lookup
# table off the version spine — message versions reference one by id, and
# the defaults are seeded (db/seeds.rb); there is no management UI yet.
class Category < ApplicationRecord
  # The name rides in every byline; the icon slot fits any emoji sequence
  # (same budget as a Boost).
  NAME_MAX_LENGTH = 64
  ICON_MAX_LENGTH = 16

  validates :name, presence: true, uniqueness: true, length: { maximum: NAME_MAX_LENGTH }
  validates :icon, presence: true, length: { maximum: ICON_MAX_LENGTH }

  scope :ordered, -> { order(:name) }

  # How a category reads anywhere it appears: icon then name.
  def label
    "#{icon} #{name}"
  end
end
