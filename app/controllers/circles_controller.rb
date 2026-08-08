# A circle's home page IS its feed — messages and pulse answers (Beats)
# merged at their record ids, newest first, one lazy-paginated stream, with a
# segmented control to narrow to check-ins only (?filter=checkins). The
# owner can also edit the circle itself (name, description). Membership and the
# active bucket are set by the base controller.
class CirclesController < Circles::BaseController
  # index/all/new/create don't operate on an existing circle, so they can't load
  # one or set a bucket. Anyone signed in can start a circle (they become its owner).
  skip_before_action :set_circle, only: %i[index all new create]

  # Only the owner edits the circle's name/description.
  before_action -> { authorize! @circle, to: :manage }, only: %i[edit update]

  # How many feed items (messages + pulse answers) a page carries.
  PER_PAGE = 10

  # Everyone gets one circle of their own; platform admins (root) are uncapped.
  CIRCLE_LIMIT_ALERT = "You can only create one circle."

  def index
    # Members ride along for the cards' avatar clusters (pictures included).
    @circles = Current.user.circles.includes(members: { avatar_attachment: :blob }).order(:name)
    @all_count = Circle.count
    # Seats waiting on your answer — accepted or declined right from this page.
    @invitations = Current.user.circle_invitations.includes(:circle, inviter: { avatar_attachment: :blob })
  end

  # Every circle on the platform, browse-only: your own are doors; the rest
  # are just names (a non-member's circle page is a 404 regardless).
  def all
    @circles = Circle.order(:name)
    # A pending seat follows you here: its circle shows as the golden card.
    @invitations_by_circle = Current.user.circle_invitations.includes(:inviter).index_by(&:circle_id)
  end

  helper_method :can_create_circle?

  def new
    return redirect_to circles_path, alert: CIRCLE_LIMIT_ALERT unless can_create_circle?
    @circle = Circle.new
  end

  def create
    return redirect_to circles_path, alert: CIRCLE_LIMIT_ALERT unless can_create_circle?

    @circle = Circle.create_with_owner(owner: Current.user, **circle_params.to_h.symbolize_keys)

    if @circle.persisted?
      redirect_to circle_path(@circle), notice: "Circle created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # The circle home: the feed by default (messages + beats merged newest-first;
  # ?filter=beats narrows to beats), or the Progress leaderboard
  # (?view=progress). The header and rail ride the first page of either view;
  # the feed's affixed strips ride its first page only, and feed pagination
  # carries just the next slice.
  def show
    @view = "progress" if params[:view] == "progress"

    if @view == "progress"
      @ledger = Circle::Ledger.new(@circle)
      load_board_chrome
      return
    end

    before = params[:before_id].presence&.to_i
    @filter = params[:filter] if params[:filter] == "beats"
    load_feed_page(before)
    return if before

    load_board_chrome
    load_feed_affixes
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
      params.expect(circle: [ :name, :description, :charter ])
    end

    # The merged feed slice for the current cursor + filter, with the cards'
    # comment counts, commenters, and boosts.
    def load_feed_page(before)
      messages = @filter == "beats" ? [] : message_page(before)
      beats = beat_page(before)

      candidates =
        messages.first(PER_PAGE).map { |m| { anchor: m.record_id, message: m } } +
        beats.first(PER_PAGE).map { |b| { anchor: b.record_id, beat: b } }
      @items = candidates.sort_by { |item| -item[:anchor] }.first(PER_PAGE)
      @more = (messages.size + beats.size) > @items.size
      @cursor = @items.last&.dig(:anchor)

      prepare_messages(@items.filter_map { |i| i[:message] })
      prepare_beats(@items.filter_map { |i| i[:beat] })
      item_record_ids = @records_by_message.values.map(&:id) + @beat_records.keys
      @comment_counts = @circle.records.active.comments
        .where(parent_id: item_record_ids).group(:parent_id).count
      @commenters_by_record = commenters_for(item_record_ids)
      @boosts_by_record = Boost.where(record_id: item_record_ids)
        .includes(creator: { avatar_attachment: :blob }).group_by(&:record_id)
    end

    # The header's roster + pulse window and the rail's "who's talking" — shared
    # by the feed and the Progress views.
    def load_board_chrome
      @pulse = @circle.pulse
      @members = @circle.roster
      @talkers = @circle.recent_posters
      @member_count = @circle.circle_memberships.count
    end

    # The feed's own affixed strips: the one actionable pulse pin, your drafts
    # pointer, your pending appointments, and — on the Commons — announcements.
    def load_feed_affixes
      @pending_pulse = pending_pulse
      @drafts_count = Message.current_in(@circle.records.listed).drafted
        .created_by(Current.user).count
      @scheduled = Message.current_in(@circle.records.listed).scheduled
        .created_by(Current.user).order(:published_at).to_a
      if @circle.commons?
        Current.allowing_unscoped_tenancy do
          @bulletins = Bulletin.current.published.includes(:record).feed_ordered.limit(3).to_a
        end
      end
    end

    # The stream carries only what the circle can see: published messages.
    # Drafts stay in their authors' drawers; scheduled ones surface only to
    # their own author, in the strip.
    def message_page(before)
      scope = Message.current_in(@circle.records.listed).published
        .order(record_id: :desc).includes(body: :rich_text_content)
      scope = scope.where(record_id: ...before) if before
      scope.limit(PER_PAGE + 1).to_a
    end

    # Pulse answers, public from their first save — every one a feed story.
    def beat_page(before)
      scope = Beat.current_in(@circle.records.listed)
        .order(record_id: :desc).includes(:rich_text_content)
      scope = scope.where(record_id: ...before) if before
      scope.limit(PER_PAGE + 1).to_a
    end

    def prepare_messages(messages)
      records = Record.where(id: messages.map(&:record_id))
        .includes(:bucket, creator: { avatar_attachment: :blob }).index_by(&:id)
      @records_by_message = messages.index_with { |message| records[message.record_id] }
    end

    # The distinct commenters on each feed item, for the cards' avatar cluster.
    # One distinct (parent, author) sweep, then hydrate the faces once.
    def commenters_for(record_ids)
      pairs = @circle.records.active.comments.where(parent_id: record_ids)
        .distinct.pluck(:parent_id, :creator_id)
      people = User.where(id: pairs.map(&:last).uniq)
        .includes(avatar_attachment: :blob).index_by(&:id)
      pairs.group_by(&:first).transform_values { |ps| ps.map { |(_, uid)| people[uid] } }
    end

    # A beat's card needs its record (answerer) and its pulse (the title).
    def prepare_beats(beats)
      @beat_records = Record.where(id: beats.map(&:record_id))
        .includes(creator: { avatar_attachment: :blob }).index_by(&:id)
      @pulse_records = Record.where(id: @beat_records.values.map(&:parent_id).uniq).index_by(&:id)
    end

    # The one actionable pin: the circle asked, you're subscribed, you haven't
    # answered this occurrence.
    def pending_pulse
      record = @circle.records.active.where(recordable_type: "Pulse").last or return
      pulse = record.recordable
      return unless pulse.last_asked_on.present?
      return unless pulse.respondents.exists?(id: Current.user.id)
      return if pulse.beats_on(pulse.last_asked_on)
        .joins(:record).where(records: { creator_id: Current.user.id }).exists?
      pulse
    end
end
