# A circle's home page previews its discussions. The owner can also edit the
# circle itself (name, description). Membership and the active bucket are set by
# the base controller.
class CirclesController < Circles::BaseController
  # index/all/new/create don't operate on an existing circle, so they can't load
  # one or set a bucket. Anyone signed in can start a circle (they become its owner).
  skip_before_action :set_circle, only: %i[index all new create]

  # Only the owner edits the circle's name/description.
  before_action -> { authorize! @circle, to: :manage }, only: %i[edit update]

  # Both the picker (index) and the board (show) are full workspace pages —
  # same app header + canvas chrome as the site admin, not the minimal `auth`
  # shell the base controller defaults to.
  layout "application"

  # How many discussions the circle home previews before the "see all" link.
  PREVIEW_COUNT = 5

  # Everyone gets one circle of their own; platform admins (root) are uncapped.
  CIRCLE_LIMIT_ALERT = "You can only create one circle."

  def index
    # Members ride along for the cards' avatar clusters (pictures included).
    @circles = Current.user.circles.includes(members: { avatar_attachment: :blob }).order(:name)
    @all_count = Circle.count
  end

  # Every circle on the platform, browse-only: your own are doors; the rest
  # are just names (a non-member's circle page is a 404 regardless).
  def all
    @circles = Circle.order(:name)
  end

  helper_method :can_create_circle?

  def new
    return redirect_to circles_path, alert: CIRCLE_LIMIT_ALERT unless can_create_circle?
    @circle = Circle.new
  end

  def create
    return redirect_to circles_path, alert: CIRCLE_LIMIT_ALERT unless can_create_circle?

    @circle = Circle.create_with_owner(name: circle_params[:name], owner: Current.user,
      description: circle_params[:description])

    if @circle.persisted?
      redirect_to circle_path(@circle), notice: "Circle created."
    else
      render :new, status: :unprocessable_entity
    end
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
    # A member may own a single circle; admins (root) are unlimited.
    def can_create_circle?
      Current.user.root? || Circle.where(owner_id: Current.user.id).none?
    end

    def circle_params
      params.expect(circle: [ :name, :description ])
    end
end
