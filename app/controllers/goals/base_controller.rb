# Base for the /goals area — an author's personal practice targets,
# independent of any site or circle. The user themself is the bucket: records
# born here are stamped to the person (see Goal), and every lookup starts from
# Record.where(bucket: Current.user), so someone else's goal is
# indistinguishable from a missing one. Lives on the app host, like circles.
module Goals
  class BaseController < ApplicationController
    layout "application"

    before_action { Current.bucket = Current.user }

    private
      def goal_records
        Record.active.goals.where(bucket: Current.user)
      end
  end
end
