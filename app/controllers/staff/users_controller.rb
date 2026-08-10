# The platform people directory (/admin/users): every user, the circles they
# belong to, and the sites they own. Root staff only — gated like the support
# desk (a bare 404 for everyone else). Users, circles, and accounts aren't
# tenanted tables (the guard watches records/missives/subscribers), so a plain
# cross-user read needs no unscoped-tenancy escape.
class Staff::UsersController < ApplicationController
  layout "application"

  before_action :require_root

  def index
    @metrics = SaasMetrics.new
    @users = User.includes(:circles).order(:name)
    # The sites each user owns, gathered in one query and bucketed by owner so
    # the view stays N+1-free (owner_id, not membership — a site's creator).
    @sites_by_owner = Account.where(owner_id: @users.map(&:id)).order(:name).group_by(&:owner_id)
  end

  private
    def require_root
      head :not_found unless Current.user&.root?
    end
end
