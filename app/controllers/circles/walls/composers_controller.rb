# The feed's compose surface: a blank message form fetched into the "modal"
# frame (the same pattern as the edit and thread modals). The form submits the
# ordinary messages#create with back=wall, landing the new post on the feed.
# Any member who can post gets it.
module Circles
  module Walls
    class ComposersController < BaseController
      def show
        authorize! @circle, to: :post
        @message = Message.new
      end
    end
  end
end
