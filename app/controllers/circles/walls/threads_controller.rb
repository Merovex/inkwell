# The Wall's thread modal: one message + its comments, fetched into the
# wall's "modal" frame (the goals-today pattern — the response carries a
# <dialog> that shows itself). Comment submits post back=wall and land here
# again, so the modal re-renders with the new comment instead of navigating
# away to the message page.
module Circles
  module Walls
    class ThreadsController < BaseController
      def show
        @record = @circle.records.listed.messages.find(params[:id])
        @message = @record.recordable
      end
    end
  end
end
