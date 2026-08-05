# Reports against a goal: a date (default today), an amount in the goal's
# unit, and a short note. Tallies thread off the goal's Record and inherit its
# reach — yours alone. Mutable: corrections amend in place; deletes trash the
# record. Edits swap inline in the tally's turbo frame (the comment/beat shape).
module Goals
  class TalliesController < BaseController
    before_action :set_goal
    before_action :set_tally, only: %i[edit update destroy]

    def create
      @tally = Tally.new(tally_params)
      if @tally.valid?
        Record.originate(@tally, parent: @goal_record)
        redirect_to after_save_path(@tally.record_id)
      else
        redirect_to goal_path(@goal_record), alert: "A tally needs an amount (and a note no longer than an old tweet)."
      end
    end

    # The one-click "today" modal: edit today's record when it exists, start
    # one otherwise. Rendered into the index's "modal" turbo frame.
    def today
      @tally = @goal.tallies.find_by(logged_on: Time.zone.today) || Tally.new(logged_on: Time.zone.today)
    end

    def edit
    end

    def update
      @tally.amend(**tally_params.to_h.symbolize_keys)
      if @tally.errors.none?
        redirect_to after_save_path(@tally_record.id)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @tally_record.trash
      redirect_to goal_path(@goal_record), notice: "Tally removed."
    end

    private
      def set_goal
        @goal_record = goal_records.find(params[:goal_id])
        @goal = @goal_record.recordable
      end

      def set_tally
        @tally_record = Record.active.tallies.where(parent_id: @goal_record.id).find(params[:id])
        @tally = @tally_record.recordable
      end

      def tally_params
        params.expect(tally: [ :logged_on, :amount, :note ])
      end

      # The today-modal logs from the index and should land back there (the
      # tiles update); everything else returns to the goal page, anchored.
      def after_save_path(tally_record_id)
        params[:back] == "goals" ? goals_path : goal_path(@goal_record, anchor: "tally_#{tally_record_id}")
      end
  end
end
