# A circle's home page previews its discussions. The owner can also edit the
# circle itself (name, description). Membership and the active bucket are set by
# the base controller.
class CirclesController < Circles::BaseController
  # index is the door from the app menu — it lists every circle you're in, so
  # it can't load a single circle or set a bucket.
  skip_before_action :set_circle, only: :index

  # Only the owner edits the circle's name/description.
  before_action -> { authorize! @circle, to: :manage }, only: %i[edit update]

  # Both the picker (index) and the board (show) are full workspace pages —
  # same app header + canvas chrome as the site admin, not the minimal `auth`
  # shell the base controller defaults to.
  layout "application"

  # How many discussions the circle home previews before the "see all" link.
  PREVIEW_COUNT = 5

  def index
    @circles = Current.user.circles.order(:name)
  end

  def show
    @pulse = @circle.pulse
    # Scheduled discussions wait in their own view; the home previews the
    # conversation as it stands (posted + in-progress).
    visible = @circle.discussions_visible_to(Current.user).where.not(status: :scheduled)
    @discussions = visible.limit(PREVIEW_COUNT)
    @discussions_count = visible.count
  end

  def edit
  end

  def update
    if @circle.update(circle_params)
      redirect_to circle_path(@circle), notice: "Circle updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def circle_params
      params.expect(circle: [ :name, :description ])
    end
end
