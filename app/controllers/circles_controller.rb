# A circle's home page is its message board: the posts (newest first) plus a
# composer. Membership and the active bucket are set by the base controller.
class CirclesController < Circles::BaseController
  def show
    @messages = @circle.messages
    @circle_message = CircleMessage.new
  end
end
