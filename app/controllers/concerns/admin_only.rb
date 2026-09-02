# Restrict a controller to whoever administers the current account: its owner
# (accounts.owner_id — per-account superuser) or a root user (platform staff).
# Denial renders the same 404 as a missing record — what admins manage is
# nobody else's business. Per-record authorization stays on the policies.
module AdminOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_admin
  end

  private
    def require_admin
      render_not_found unless Current.user&.administers?(Current.account)
    end
end
