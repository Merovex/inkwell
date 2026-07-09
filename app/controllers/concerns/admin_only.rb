# Restrict a controller to domain admins. Denial renders the same 404 as a
# missing record — what admins manage is nobody else's business. This is the one
# gate for the install-management sections (settings, subscribers, broadcasts,
# analytics); per-record authorization (creator-or-admin) stays on the policies.
module AdminOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_admin
  end

  private
    def require_admin
      render_not_found unless Current.user&.domain_admin?
    end
end
