# Restrict a controller to the current account's owner — stricter than
# AdminOnly, which also admits root (platform staff). For what is the
# author's alone even from us: their subscriber list leaving the building.
# Denial renders the same 404 as a missing record.
module OwnerOnly
  extend ActiveSupport::Concern

  included do
    before_action :require_owner
  end

  private
    def require_owner
      render_not_found unless Current.account.owner == Current.user
    end
end
