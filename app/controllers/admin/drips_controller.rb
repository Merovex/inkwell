# Managing drip campaigns — recordables on the spine (like authors), but with
# an `active` flag instead of a publish regime. Domain-admin only. Content edits
# version the campaign; activate/deactivate lands as a tracked revision too.
class Admin::DripsController < Admin::BaseController
  include DripScoped
  skip_before_action :set_record, only: %i[index dashboard new create]
  before_action -> { authorize! @record, to: :view }, only: :show
  before_action -> { authorize! @record, to: :manage }, only: %i[edit update destroy activate reorder]

  def index
    @drips = Drip.current.joins(:record).includes(:creator).order("records.created_at DESC")
  end

  # Overview: send/skip totals, a delivered-per-day history, and the next
  # scheduled sends across every active stream.
  def dashboard
    @subscribers_count = Stream.select(:subscriber_id).distinct.count
    @delivered_count = DropDelivery.status_sent.count
    @skipped_count = DropDelivery.status_skipped.count
    @active_count = Drip.live.count
    @opened_count = DropDelivery.where.not(opened_at: nil).count
    @clicked_count = DropDelivery.where.not(clicked_at: nil).count
    @history = delivered_by_day
    @upcoming = upcoming_sends
  end

  def show
    @drops = @drip.drops
  end

  def new
    @drip = Drip.new
  end

  def create
    @drip = Drip.new(drip_params.merge(event: :created))

    if @drip.valid?
      Record.originate(@drip)
      redirect_to admin_drip_path(@drip.record), notice: "Drip created — add its drops below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @drip = @record.revise(event: :updated, **drip_params.to_h.symbolize_keys)

    if @drip.errors.none?
      redirect_to admin_drip_path(@record), notice: "Drip saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Activate (or deactivate) the campaign — flips `active` as a tracked revision.
  # Active drips enroll newly-confirmed subscribers; deactivating stops new
  # enrollments (in-flight streams finish).
  def activate
    on = params[:active] != "false"
    @record.revise(event: (on ? :published : :unpublished), active: on)
    redirect_to admin_drip_path(@record), notice: (on ? "Drip activated." : "Drip deactivated.")
  end

  def destroy
    @record.trash
    redirect_to admin_drips_path, notice: "Drip moved to trash."
  end

  # Drag-reorder the drip's drops: PATCH drop_record_ids[] in the new order;
  # the child Records' positions are rewritten 1..n for this drip only.
  def reorder
    ids = Array(params[:drop_record_ids]).map(&:to_i)
    Record.transaction do
      ids.each_with_index do |drop_record_id, i|
        Record.where(id: drop_record_id, parent_id: @record.id).update_all(position: i + 1)
      end
    end
    head :no_content
  end

  private
    def drip_params
      params.expect(drip: [ :title, :trigger ])
    end

    # Delivered count per day over the last 90 days, every day present (so the
    # line is continuous). Grouped in Ruby to stay portable across databases.
    def delivered_by_day
      window = 90.days.ago.to_date
      counts = DropDelivery.status_sent.where("sent_at >= ?", window).pluck(:sent_at)
        .group_by(&:to_date).transform_values(&:size)
      (window..Date.current).index_with { |day| counts[day] || 0 }
    end

    # The next scheduled send for each active stream (earliest undelivered future
    # Drop), soonest first. N+1 by stream — fine at newsletter scale; revisit if
    # active streams grow large.
    def upcoming_sends(limit: 10)
      now = Time.current
      Stream.active.includes(:subscriber, :deliveries).filter_map do |stream|
        drip = stream.drip or next
        recorded = stream.deliveries.map(&:drop_record_id)
        drip.drops
          .reject { |drop| recorded.include?(drop.record_id) }
          .map { |drop| { subscriber: stream.subscriber, drip:, send_at: drop.send_at_for(stream) } }
          .select { |row| row[:send_at] > now }
          .min_by { |row| row[:send_at] }
      end.sort_by { |row| row[:send_at] }.first(limit)
    end
end
