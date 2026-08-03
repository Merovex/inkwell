# A circle's home page is its message board: the posts (newest first) plus a
# composer. Membership and the active bucket are set by the base controller.
class CirclesController < Circles::BaseController
  # index is the door from the app menu — it lists every circle you're in, so
  # it can't load a single circle or set a bucket.
  skip_before_action :set_circle, only: :index

  def index
    @circles = Current.user.circles.order(:name)
  end

  def show
    @messages = @circle.messages
    @circle_message = CircleMessage.new
  end
end
