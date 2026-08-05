# The circle's membership page (⋯ menu → "Membership"): who's in, the invite
# form (any member may extend a seat — CirclePolicy#invite?), and the pending
# invitations. Basecamp's "Who's on this project?", circle-sized.
module Circles
  class MembersController < BaseController
    def index
      @members = @circle.roster
      @pending_invitations = @circle.invitations.includes(:user, :inviter)
    end
  end
end
