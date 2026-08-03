# Base for the /circles area — an author's accountability circles, independent
# of any site. Authentication is inherited from ApplicationController; each
# request then resolves the circle from its slug, authorizes membership through
# CirclePolicy (which never consults account ownership — a non-member gets the
# same 404 as a missing record), and sets the circle as the active bucket so new
# records are stamped to it rather than to a site.
module Circles
  class BaseController < ApplicationController
    layout "auth"

    before_action :set_circle

    private
      def set_circle
        @circle = Circle.find(params[:circle_id] || params[:id])
        authorize! @circle, to: :show
        Current.bucket = @circle
      end
  end
end
