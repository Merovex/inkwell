# Accepting an invitation = creating its acceptance: membership in, invitation
# out, atomically (CircleInvitation#accept). The invitee's move alone — the
# scoped find is the authorization, and like InvitationsController this can't
# inherit Circles::BaseController (the invitee isn't a member yet).
module Circles
  module Invitations
    class AcceptancesController < ApplicationController
      def create
        invitation = Current.user.circle_invitations.find(params[:invitation_id])
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
    end
  end
end
