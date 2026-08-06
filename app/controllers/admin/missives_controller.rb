# Contact-form submissions — domain-admin only. A read feed of confirmed
# Missives with a Trash tab; destroy moves one to Trash (no hard delete — the
# purge sweep is the only destroyer). There's no create/edit: messages arrive
# from the public /contact form and are confirmed by double opt-in. Unconfirmed
# submissions never appear here (the purge job sweeps them).
class Admin::MissivesController < Admin::BaseController
  # One state at a time; the header links between them. Names match the model
  # scopes (Missive.active / Missive.trashed).
  STATES = %w[ active trashed ].freeze

  def index
    @state = STATES.include?(params[:state]) ? params[:state] : "active"
    @missives = Current.account.missives.public_send(@state)
    @counts = { "active" => Current.account.missives.active.count, "trashed" => Current.account.missives.trashed.count }
  end

  def show
    @missive = Current.account.missives.find(params[:id])
  end

  def destroy
    Current.account.missives.find(params[:id]).trash!
    redirect_to admin_missives_path(state: params[:state]), notice: "Message moved to Trash."
  end
end
