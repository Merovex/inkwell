# Board categories are a site's shared vocabulary (each account names its
# own) — renames rewrite how every historical message reads — so tending
# them is the admin's job.
class CategoryPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
