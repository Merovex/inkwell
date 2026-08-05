# Who may do what in a Circle. Deliberately account-free: a circle's authority
# is its own membership graph, never press ownership — so this policy leans on
# the subject (the Circle) and the user, and never touches Current.account or
# the inherited admin? helper.
class CirclePolicy < ApplicationPolicy
  # Members see the circle and post to its board.
  def show? = member? ? allow! : deny!(:not_a_member)
  def post? = member? ? allow! : deny!(:not_a_member)

  # Circles are invite-only, and any member may extend an invitation — the
  # invitation records who vouched.
  def invite? = member? ? allow! : deny!(:not_a_member)

  # Only the owner manages the circle itself (settings, membership, deletion).
  def manage? = owner? ? allow! : deny!(:not_owner)

  private
    def member? = subject.member?(user)
    def owner?  = user.present? && subject.owner_id == user.id
end
