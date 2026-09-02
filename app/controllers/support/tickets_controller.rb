# The user side of the App's help desk (/support): your own tickets, bucketed
# to you exactly like Goals — someone else's ticket is indistinguishable from
# a missing one. Root staff may open any ticket by the same URL (the desk
# queue links here), inside the deliberate cross-bucket escape.
class Support::TicketsController < ApplicationController
  layout "application"

  before_action { Current.bucket = Current.user }

  def index
    # One state at a time, open by default — closed history stays a click
    # away, not in the default view (the Subscribers pattern).
    @state = Ticket::STATUSES.include?(params[:state]) ? params[:state] : "open"
    scope = Ticket.current_in(ticket_records.listed)
    @counts = scope.group(:status).count
    @tickets = scope.where(status: @state).order(created_at: :desc)
  end

  def new
    @ticket = Ticket.new
  end

  def create
    @ticket = Ticket.new(ticket_params)
    if @ticket.valid?
      Record.originate(@ticket)
      notify_staff
      redirect_to ticket_path(@ticket.record), notice: "Ticket opened — we'll get back to you here."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @record = find_record
    @ticket = @record.recordable
  end

  private
    def ticket_records
      Record.active.tickets.where(bucket: Current.user)
    end

    # The requester's own ticket, or any ticket for root staff.
    def find_record
      if Current.user&.root?
        Current.allowing_unscoped_tenancy { Record.active.tickets.find(params[:id]) }
      else
        ticket_records.find(params[:id])
      end
    end

    def ticket_params
      params.expect(ticket: %i[ title content ])
    end

    # The bell for platform staff — a new ticket needs eyes. Bell-only kind:
    # nothing here is more urgent than the next digest, and staff live in the
    # app anyway.
    def notify_staff
      User.root.where.not(id: Current.user.id).find_each do |staff|
        Notification.deliver(@ticket.record, to: staff, kind: "ticket_opened")
      end
    end
end
