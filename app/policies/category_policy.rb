# Board categories are install-wide vocabulary — renames rewrite how every
# historical message reads — so tending them is the admin's job.
class CategoryPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
