# The broadcasts dashboard is install-wide send analytics — the domain admin's
# to see. (Sending a specific post is authorized separately, on the post's
# record.)
class BroadcastPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
