# Marking the bell read = creating a reading: one POST stamps every unread
# row. The flyout calls it on open (notifications_controller.js); the index
# page performs the same read as a side effect of visiting.
module Notifications
  class ReadingsController < ApplicationController
    def create
      Current.user.notifications.unread.update_all(read_at: Time.current)
      head :no_content
    end
  end
end
