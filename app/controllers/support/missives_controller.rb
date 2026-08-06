# The platform support inbox: support@kindredquill.com mail-in, read by root
# staff on the app host (/missives). Platform missives have no account, so the
# whole controller runs inside the deliberate tenancy escape (ADR 0017) —
# scoped to Missive.platform, never any Site's mail. Gated exactly like
# Mission Control (Admin::JobsBaseController): non-root gets a bare 404.
class Support::MissivesController < ApplicationController
  before_action :require_root
  around_action :allow_platform_scope

  STATES = %w[ active trashed ].freeze

  def index
    @state = STATES.include?(params[:state]) ? params[:state] : "active"
    @missives = Missive.platform.public_send(@state)
    @counts = STATES.index_with { |state| Missive.platform.public_send(state).count }
  end

  def show
    @missive = Missive.platform.find(params[:id])
  end

  def destroy
    Missive.platform.find(params[:id]).trash!
    redirect_to missives_path, notice: "Message moved to Trash."
  end

  private
    def require_root
      head :not_found unless Current.user&.root?
    end

    def allow_platform_scope(&)
      Current.allowing_unscoped_tenancy(&)
    end
end
