# Your own seat in a circle. destroy = leaving: a member's own act, from the
# circle page's ⋯ menu. The owner can't leave — they delete the circle or hand
# it off; guarding here keeps a circle from ever being orphaned.
module Circles
  class MembershipsController < BaseController
    def destroy
      if @circle.commons?
        redirect_to circle_path(@circle), alert: "The Commons is everyone's — there's no leaving it."
      elsif @circle.owner_id == Current.user.id
        redirect_to circle_path(@circle), alert: "You own this circle — hand it off or delete it instead."
      else
        @circle.circle_memberships.find_by!(user_id: Current.user.id).destroy
        redirect_to circles_path, notice: "You left #{@circle.name}."
      end
    end
  end
end
