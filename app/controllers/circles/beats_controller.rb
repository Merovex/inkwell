# A member's answer to the current check-in occurrence. One beat per member per
# occurrence — a second submission edits the first (a tracked version, since
# Beat is immutable). Answering requires circle membership; a beat is stamped to
# the circle bucket and threads off the pulse's Record.
module Circles
  class BeatsController < BaseController
    before_action -> { authorize! @circle, to: :post }

    def create
      @record = @circle.records.active.where(recordable_type: "Pulse").find(params[:pulse_id])
      @pulse = @record.recordable
      occurrence = @pulse.current_occurrence || Time.zone.today

      beat = @pulse.beats_on(occurrence).find_by(creator_id: Current.user.id)
      if beat
        beat.record.revise(event: :updated, content: beat_params[:content])
      elsif beat_params[:content].present?
        Record.originate(
          Beat.new(content: beat_params[:content], asked_on: occurrence, creator: Current.user),
          parent: @record)
      end

      redirect_to circle_pulse_path(@circle, @record, anchor: "beats")
    end

    private
      def beat_params
        params.expect(beat: [ :content ])
      end
  end
end
