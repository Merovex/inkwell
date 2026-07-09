# The subscriber list is install-wide, personal data — managing it (viewing the
# roster, exporting, honoring an unsubscribe) is the domain admin's job.
class SubscriberPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
