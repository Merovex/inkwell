# Extending and answering circle invitations. Deliberately NOT a
# Circles::BaseController: the invitee answering (accept/destroy-as-decline) is
# by definition not yet a member, so the membership 404 in set_circle would
# lock them out of their own invitation. Authorization here is the invitation
# row itself — plus the invite? policy for extending one.
module Circles
  class InvitationsController < ApplicationController
    # A member offers a seat, addressed to an existing Inkwell user by email.
    def create
      circle = Circle.find(params[:circle_id])
      authorize! circle, to: :invite

      invitee = User.find_by(email_address: params[:email_address])
      return redirect_to circle_members_path(circle), alert: "No Inkwell author with that address — they need to join Inkwell first." unless invitee

      invitation = circle.invitations.create(user: invitee, inviter: Current.user)
      if invitation.persisted?
        Notification.deliver(invitation, to: invitee, kind: "invited")
        redirect_to circle_members_path(circle), notice: "#{invitee.display_name} has been invited."
      else
        redirect_to circle_members_path(circle), alert: invitation.errors.full_messages.to_sentence + "."
      end
    end

    # Accepting is the invitee's move alone; the scoped find is the authorization.
    def accept
      invitation = Current.user.circle_invitations.find(params[:id])
      circle = invitation.circle

      inviter = invitation.inviter
      if (membership = invitation.accept)
        # The inviter deserves to know their invitation landed (bell-only).
        Notification.deliver(membership, to: inviter, kind: "invitation_accepted") unless inviter == Current.user
        redirect_to circle_path(circle), notice: "Welcome to #{circle.name}."
      else
        redirect_to circles_path, alert: "#{circle.name} is full."
      end
    end

    # Decline (the invitee's own) or revoke (the inviter's, or any of the
    # owner's). Anyone else gets the same 404 as a missing record.
    def destroy
      invitation = Circle.find(params[:circle_id]).invitations.find(params[:id])
      permitted = [ invitation.user_id, invitation.inviter_id, invitation.circle.owner_id ]
      raise ActiveRecord::RecordNotFound unless permitted.include?(Current.user.id)

      # Revoked or declined: the announcement goes with it (the no-ghosts rule
      # — an invitation that never resolves shouldn't echo in the bell).
      # destroy_all, deliberately: delete_all on a :nullify association
      # nullifies rather than deletes.
      invitation.notifications.destroy_all
      invitation.destroy
      if invitation.user_id == Current.user.id
        redirect_to circles_path, notice: "Invitation declined."
      else
        redirect_to circle_members_path(invitation.circle), notice: "Invitation revoked."
      end
    end
  end
end
