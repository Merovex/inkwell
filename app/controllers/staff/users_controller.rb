# The platform people directory (/admin/users): every user, the circles they
# belong to, and the sites they own. Root staff only — gated like the support
# desk (a bare 404 for everyone else). Users, circles, and accounts aren't
# tenanted tables (the guard watches records/missives/subscribers), so a plain
# cross-user read needs no unscoped-tenancy escape.
class Staff::UsersController < ApplicationController
  layout "application"

  require_root

  def index
    @metrics = SaasMetrics.new
    @users = User.includes(:circles).order(:name)
    # Every site, bucketed by owner, so the view stays N+1-free (owner_id, not
    # membership — a site's creator). No owner filter: @users is every user.
    @sites_by_owner = Account.order(:name).group_by(&:owner_id)
  end
end
