# Base for the Inkwell admin backend. Every action requires an authenticated
# session (inherited from ApplicationController's require_authentication) *and*
# the domain-admin role (AdminOnly). The backend is the author's alone — a
# signed-in non-admin gets the same 404 as a missing record.
#
# The pre-login entry points — sign-in (SessionsController), first-run setup
# (SetupsController), open self-registration (SignupsController), and the static
# style pages (StaticController) — deliberately stay on ApplicationController
# with allow_unauthenticated_access, since you can't be an admin before you're in.
class Admin::BaseController < ApplicationController
  include AdminOnly
end
