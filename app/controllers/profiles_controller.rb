# A member's public face (/profiles/:id): picture, handle, and the circles
# they belong to. Sign-in is required (ApplicationController's default) — this
# is one member looking at another, never an anonymous visitor. Sites a member
# owns live on their own path (the account switcher), not here.
class ProfilesController < ApplicationController
  layout "application"

  def show
    @user = User.find(params[:id])
    # Your own page shows all your circles; someone else's shows only the ones
    # you share (the Commons is universal, so it's never an affiliation worth
    # listing). Scoped in SQL, so an unshared circle never leaks a name.
    @memberships = circle_memberships_for(@user).includes(:circle).order("circles.name")
  end

  private
    def own_profile? = @user == Current.user
    helper_method :own_profile?

    def circle_memberships_for(user)
      circles = own_profile? ? user.circles : Current.user.circles.where(id: user.circle_ids)
      user.circle_memberships.where(circle: circles.where(commons: false))
    end
end
