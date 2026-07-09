# The install's settings are the domain admin's to tend — they shape the whole
# public site, so only the admin may view or change them.
class SettingPolicy < ApplicationPolicy
  def manage?
    return allow! if admin?

    deny! :not_admin
  end
end
