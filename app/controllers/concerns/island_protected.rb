# Origin lockdown for the dynamic islands — the public endpoints the edge
# Worker proxies to Rails after the static cut-over (phase-2 §2.5, bot-
# protection plan §2a). Every legitimate island request transits the Worker,
# so the Worker vouches for its traffic with a shared-secret header; anything
# arriving without it (a bot posting straight to the origin it scraped from
# DNS history) is turned away before any other guard runs.
#
# Unprovisioned (no island_auth_secrets in credentials — dev, test, and
# production until cut-over) the check is a no-op, so Rails keeps serving
# these pages directly. Two secrets are accepted so the Worker can roll to a
# new one without a coordinated deploy: add the next secret here, move the
# Worker, then drop the old one.
module IslandProtected
  extend ActiveSupport::Concern

  included do
    before_action :require_island_auth
  end

  private
    def require_island_auth
      secrets = Array(Rails.configuration.x.island_auth_secrets)
      return if secrets.empty?

      presented = request.headers["X-Island-Auth"].to_s
      head :forbidden if secrets.none? { |secret| ActiveSupport::SecurityUtils.secure_compare(presented, secret) }
    end
end
