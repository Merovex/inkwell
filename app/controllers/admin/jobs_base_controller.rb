# Base for the Mission Control jobs dashboard (config.mission_control.jobs.
# base_controller_class): normal session auth via ApplicationController, then
# platform staff only — queues are platform-wide (every tenant's jobs), so the
# gate is the global root role, not per-account ownership. Non-root gets the
# same 404 as a missing record: what exists is nobody's business but its
# audience's.
class Admin::JobsBaseController < ApplicationController
  require_root

  private
    # Inside the engine even main_app helpers keep the /jobs script name, so
    # the sign-in redirect is pinned literally. The engine mounts only on the
    # app host, where sign-in is always /session/new.
    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to "/session/new"
    end
end
