# The broadcasts dashboard: every post that's been emailed (or is scheduled to
# be), with its newsletter metrics. Domain-admin only. Read-only — sending is
# driven from the post page (Admin::Posts::BroadcastsController).
class Admin::BroadcastsController < ApplicationController
  include AdminOnly

  def index
    @broadcasts = Broadcast.includes(:record).order(created_at: :desc)
  end
end
