# A bucket for authors, not sites: an accountability circle with a message
# board (and, later, a running chat and newsletter-swap coordination). Owned by
# a User — like a Facebook group, size-capped — and it owns Records on the spine
# just as an Account does, through the polymorphic :bucket association. Its slug
# is its own (under /circles), unrelated to any site slug.
class Circle < ApplicationRecord
  include Sluggable
  self.slug_param_only = true

  # The ceiling no circle may exceed, whatever its member_limit says: Dunbar's
  # number — past ~150 people a group can't sustain real relationships, and a
  # circle is nothing but those.
  MEMBER_HARD_CAP = 150

  belongs_to :owner, class_name: "User"

  has_many :circle_memberships, dependent: :destroy
  has_many :members, through: :circle_memberships, source: :user
  # Standing offers of a seat — see CircleInvitation; circles are invite-only.
  has_many :invitations, class_name: "CircleInvitation", dependent: :destroy
  # The circle's content on the spine — board messages today (bucket_type
  # "Circle"). Mirrors Account#records; every circle query scopes through here.
  has_many :records, as: :bucket, dependent: :destroy

  validates :name, presence: true
  validates :member_limit, numericality: { only_integer: true, greater_than: 0,
    less_than_or_equal_to: MEMBER_HARD_CAP }, allow_nil: true

  # The discussions: current versions of this circle's Messages, newest first
  # (a board reads most-recent-first). The bucket-owned twin of
  # Account#messages; the query anchors on records.bucket_id, so it satisfies
  # the tenancy guard. `listed` hides archived discussions; #archived_messages
  # surfaces them.
  def messages
    discussions_from(records.listed)
  end

  def archived_messages
    discussions_from(records.archived)
  end

  # This circle's check-ins (recurring questions). A circle has one active Pulse
  # in practice, but the spine allows more; #pulse is the current one for the home.
  def pulses
    Pulse.where(id: records.active.where(recordable_type: "Pulse").select(:recordable_id))
      .order(record_id: :desc)
  end

  def pulse = pulses.live.first

  # The discussions a given member may see: published ones for everyone, plus
  # unpublished (draft/scheduled) ones only for their author — and the circle
  # owner sees every unpublished one, the circle-flavored twin of
  # RecordPolicy's "creator or admin".
  def discussions_visible_to(user, scope: messages)
    return scope if user && owner_id == user.id

    scope.where(status: :published).or(scope.where(creator_id: user&.id))
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

  # The moderation override for records in this bucket: the circle's owner. The
  # bucket-owner interface Record#moderatable_by? leans on (Account answers this
  # with account-admin).
  def moderated_by?(user) = user.present? && owner_id == user.id

  # The circle's effective seat ceiling: its own member_limit if set, but never
  # more than the hard cap — nil member_limit means "up to the cap", not
  # unlimited.
  def seat_cap
    [ member_limit, MEMBER_HARD_CAP ].compact.min
  end

  # At capacity? Counts every seat, owner included.
  def full?
    circle_memberships.count >= seat_cap
  end

  # The members as the avatar cluster reads them: owner first, then by name.
  # Uses the association as loaded (index preloads it); otherwise brings
  # avatars along.
  def roster
    list = members.loaded? ? members.to_a : members.includes(avatar_attachment: :blob).to_a
    list.sort_by { |member| [ member.id == owner_id ? 0 : 1, member.name.to_s ] }
  end

  def to_s = name

  private
    def discussions_from(record_scope)
      Message
        .where(id: record_scope.where(recordable_type: "Message").select(:recordable_id))
        .includes(:record, creator: { avatar_attachment: :blob }, body: :rich_text_content)
        .order(record_id: :desc)
    end
end
