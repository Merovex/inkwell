# An author's goals: set the practice (title, unit, optional target), then
# report against it with Tallies (Goals::TalliesController). Goals are mutable
# recordables — edits amend in place, no versions — and deletes go through the
# record's trash like everything else on the spine.
class GoalsController < Goals::BaseController
  before_action :set_goal, only: %i[show edit update destroy]

  def index
    @goals = Goal.current_in(goal_records.listed).order(created_at: :desc)
    @archived_count = goal_records.archived.count
  end

  # Retired goals — set aside, tallies intact, one click from coming back.
  def archived
    @goals = Goal.current_in(goal_records.archived).order(created_at: :desc)
  end

  def new
    @goal = Goal.new
  end

  def create
    @goal = Goal.new(goal_params)
    if @goal.valid?
      Record.originate(@goal)
      redirect_to goal_path(@goal.record)
    else
      # The form lives in a modal; a (rare — the controls constrain input)
      # server-side miss lands back on the index with the reason.
      redirect_to goals_path, alert: @goal.errors.full_messages.to_sentence
    end
  end

  def show
    @tallies = @goal.tallies
    @tally = Tally.new(logged_on: Time.zone.today)
  end

  def edit
  end

  def update
    @goal.amend(**goal_params.to_h.symbolize_keys)
    if @goal.errors.none?
      redirect_to goal_path(@record)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.trash
    redirect_to goals_path, notice: "Goal moved to trash."
  end

  private
    def set_goal
      @record = goal_records.find(params[:id])
      @goal = @record.recordable
    end

    def goal_params
      params.expect(goal: [ :title, :unit, :target, :per, displays: [] ])
    end
end
