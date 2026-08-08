# Base for the /circles area — an author's accountability circles, independent
# of any site. Authentication is inherited from ApplicationController; each
# request then resolves the circle from its slug, authorizes membership through
# CirclePolicy (which never consults account ownership — a non-member gets the
# same 404 as a missing record), and sets the circle as the active bucket so new
# records are stamped to it rather than to a site.
module Circles
  class BaseController < ApplicationController
    # Circle pages are full workspace pages — app header + canvas chrome.
    # (The minimal "auth" card shell is for sign-in ceremonies; defaulting to
    # it here kept producing floating, centered pages.)
    layout "application"

    before_action :set_circle

    private
      def set_circle
        @circle = Circle.find(params[:circle_id] || params[:id])
        authorize! @circle, to: :show
        Current.bucket = @circle
      end

      # The board chrome shared by the three views (the feed, Pulse Checks, and
      # Progress): the header's roster + pulse window and the rail's who's
      # talking. Each view renders the same _board shell around its own body.
      def load_board_chrome
        @pulse = @circle.pulse
        @members = @circle.roster
        @member_count = @circle.circle_memberships.count
        @talkers = @circle.recent_posters
      end
  end
end
