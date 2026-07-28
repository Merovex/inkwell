# Base for the Inkwell admin backend. Every action requires an authenticated
# session (inherited from ApplicationController's require_authentication) *and*
# the domain-admin role (AdminOnly). The backend is the author's alone — a
# signed-in non-admin gets the same 404 as a missing record.
#
# The pre-login entry points — sign-in (SessionsController), first-run setup
# (SetupsController), and open self-registration (SignupsController) —
# deliberately stay on ApplicationController with allow_unauthenticated_access,
# since you can't be an admin before you're in. They live outside /admin;
# everything under /admin goes through this gate.
class Admin::BaseController < ApplicationController
  include AdminOnly

  before_action :require_account_membership

  private
    # Resolving a slug from the URL identifies an account; it doesn't grant
    # access. Non-members get the same 404 as a wrong slug — membership is
    # never confirmed to outsiders (ADR 0018).
    def require_account_membership
      return unless AccountHost.enforced?
      raise ActiveRecord::RecordNotFound unless Current.account&.member?(Current.user)
    end
end
