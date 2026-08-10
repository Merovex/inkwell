# A ticket's status, updated by root staff (the desk's Mark-resolved/closed/
# reopen buttons). The change is a revision on the spine — the audit trail is
# the version history.
class Support::StatusesController < ApplicationController
  before_action :require_root

  def update
    status = params.require(:status)
    head :unprocessable_entity and return unless Ticket::STATUSES.include?(status)

    record = Current.allowing_unscoped_tenancy { Record.active.tickets.find(params[:ticket_id]) }
    record.revise(event: :updated, status: status)
    notify_requester(record)
    redirect_to ticket_path(record), notice: "Ticket marked #{status}."
  end

  private
    def require_root
      head :not_found unless Current.user&.root?
    end

    # Ring the requester's bell so they learn their ticket moved — never the
    # staffer who flipped it (your own actions don't notify you). Bell-only,
    # like the ticket-opened ring: nothing here beats the next digest.
    def notify_requester(record)
      return if record.bucket == Current.user

      Notification.deliver(record, to: record.bucket, kind: "ticket_updated")
    end
end
