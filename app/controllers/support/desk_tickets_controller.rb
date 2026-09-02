# The staff side of the help desk: every user's tickets, one status at a
# time, at /admin/tickets on the bare app host. Root staff only — gated like
# Mission Control (a bare 404 for everyone else). Rows link to the shared
# ticket page, where the status controls live.
class Support::DeskTicketsController < ApplicationController
  layout "application"

  require_root

  def index
    @state = Ticket::STATUSES.include?(params[:state]) ? params[:state] : "open"
    Current.allowing_unscoped_tenancy do
      @tickets = Ticket.current_in(Record.active.tickets).where(status: @state)
                       .includes(:record, :creator).order(created_at: :desc).to_a
      @counts = Ticket.current_in(Record.active.tickets).group(:status).count
    end
  end
end
