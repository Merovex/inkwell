# A per-person invitation into a Circle — the "invitation" JoinCode's comment
# reserved the word for. Circles are invite-only: this row is the only door in.
# Its existence IS the pending state — accepting converts it to a membership,
# declining (or revoking) just destroys it. The inviter is recorded for the
# same reason a JoinCode belongs to its owner: admission traces to whoever
# vouched.
class CircleInvitation < ApplicationRecord
  belongs_to :circle
  belongs_to :user # the invitee
  belongs_to :inviter, class_name: "User"
  # The bell rows announcing this invitation. They OUTLIVE acceptance (the
  # announcement is history, stamped with its own copy); revoking/declining
  # removes them explicitly in the controller — the no-ghosts rule.
  has_many :notifications, as: :source, dependent: :nullify

  validates :user_id, uniqueness: { scope: :circle_id, message: "already has an invitation" }
  validate :invitee_not_already_a_member, on: :create
  validate :circle_has_room, on: :create

  # Take the seat: membership in, invitation out, atomically. The membership's
  # own validation re-checks capacity — the circle may have filled since the
  # invite went out — so nil (rolled back) means "full", not a bug.
  def accept
    transaction do
      membership = circle.circle_memberships.create(user: user)
      raise ActiveRecord::Rollback unless membership.persisted?
      destroy!
      membership
    end
  end

  private
    def invitee_not_already_a_member
      errors.add(:user, "is already a member") if circle&.member?(user)
    end

    def circle_has_room
      errors.add(:base, "Circle is full") if circle&.full?
    end
end
