# A bucket for authors, not presses: an accountability circle with a message
# board (and, later, a running chat and newsletter-swap coordination). Owned by
# a User — like a Facebook group, size-capped — and it owns Records on the spine
# just as an Account does, through the polymorphic :bucket association. Its slug
# is its own (under /circles), unrelated to any press slug.
class Circle < ApplicationRecord
  include Sluggable
  self.slug_param_only = true

  belongs_to :owner, class_name: "User"

  has_many :circle_memberships, dependent: :destroy
  has_many :members, through: :circle_memberships, source: :user
  # The circle's content on the spine — board messages today (bucket_type
  # "Circle"). Mirrors Account#records; every circle query scopes through here.
  has_many :records, as: :bucket, dependent: :destroy

  validates :name, presence: true

  # The board: current versions of this circle's live CircleMessages, newest
  # first (a board reads most-recent-first). The account-scoped `.messages`
  # counterpart for a circle; the query anchors on records.bucket_id, so it
  # satisfies the tenancy guard.
  def messages
    CircleMessage
      .where(id: records.active.where(recordable_type: "CircleMessage").select(:recordable_id))
      .includes(:rich_text_content, creator: { avatar_attachment: :blob }, record: :boosts)
      .order(record_id: :desc)
  end

  # Birth of a circle: the circle plus its owner's membership, atomically —
  # the same shape as Account.create_with_owner. The owner's seat counts
  # against member_limit like any other.
  def self.create_with_owner(name:, owner:, **attrs)
    circle = new(name: name, owner: owner, **attrs)
    transaction do
      circle.circle_memberships.create!(user: owner, role: "owner") if circle.save
    end
    circle
  end

  def member?(user)
    return false unless user
    circle_memberships.exists?(user_id: user.id)
  end

  # At capacity? nil member_limit means uncapped. Counts every seat, owner
  # included.
  def full?
    member_limit.present? && circle_memberships.count >= member_limit
  end

  def to_s = name
end
