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
    Pulse.current_in(records.active).order(record_id: :desc)
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

  # At capacity? Counts every seat, owner included. The Commons never fills —
  # the whole platform is its membership.
  def full?
    return false if commons?
    circle_memberships.count >= seat_cap
  end

  # The town square: the ONE platform-wide circle (partial unique index).
  # Everyone belongs — invitation-free, cap-free, no leaving; new users join
  # at signup (User#join_commons). Bulletins affix to its Wall.
  def self.commons = find_by(commons: true)

  # Console-run once (like Tenant Zero): create the Commons and seat every
  # existing user. Idempotent — re-running seats only whoever's missing.
  def self.provision_commons(owner:)
    transaction do
      commons = find_by(commons: true) || create_with_owner(name: "Commons", owner: owner,
        commons: true, description: "Everyone on Kindred Quill — announcements, questions, and shop talk.")
      seats = User.where.not(id: commons.circle_memberships.select(:user_id)).pluck(:id).map do |user_id|
        { circle_id: commons.id, user_id: user_id, role: "member",
          created_at: Time.current, updated_at: Time.current }
      end
      CircleMembership.insert_all(seats) if seats.any?
      commons
    end
  end

  # The members as the avatar cluster reads them: owner first, then by name.
  # Uses the association as loaded (index preloads it); otherwise brings
  # avatars along.
  def roster
    list = members.loaded? ? members.to_a : members.includes(avatar_attachment: :blob).to_a
    list.sort_by { |member| [ member.id == owner_id ? 0 : 1, member.name.to_s ] }
  end

  # The charter as the sidebar's "decided here" reads it: the owner's short
  # agreement lines, one per line, blanks dropped.
  def decisions
    charter.to_s.lines.map(&:strip).reject(&:empty?)
  end

  # Members who posted to the board (a message or a check-in) within the given
  # window — the "who's talking" cluster. Owner-first, then by name, like the
  # roster.
  def recent_posters(since: 30.days.ago)
    poster_ids = records.active.where(recordable_type: %w[Message Beat])
      .where(created_at: since..).distinct.pluck(:creator_id)
    list = members.where(id: poster_ids).includes(avatar_attachment: :blob).to_a
    list.sort_by { |member| [ member.id == owner_id ? 0 : 1, member.name.to_s ] }
  end

  def to_s = name

  private
    def discussions_from(record_scope)
      Message.current_in(record_scope)
        .includes(:record, creator: { avatar_attachment: :blob }, body: :rich_text_content)
        .order(record_id: :desc)
    end
end
