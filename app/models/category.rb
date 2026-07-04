# A message-board category, Basecamp style: an emoji icon and a name, worn
# in the message's byline ("📢 Announcement by Ben Wilson"). A plain lookup
# table off the version spine — message versions reference one by id, and
# the defaults are seeded (db/seeds.rb); there is no management UI yet.
class Category < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :icon, presence: true

  scope :ordered, -> { order(:name) }

  # How a category reads anywhere it appears: icon then name.
  def label
    "#{icon} #{name}"
  end
end
