# A member's answer to the current check-in occurrence. One beat per member per
# occurrence — a second submission edits the first (a tracked version, since
# Beat is immutable). Answering requires circle membership; a beat is stamped to
# the circle bucket and threads off the pulse's Record. Edits are the author's
# alone, inline in the answer's turbo frame (the same shape as comment edits).
module Circles
  class BeatsController < BaseController
    before_action :set_pulse
    before_action -> { authorize! @circle, to: :post }, only: :create
    before_action :set_beat, only: %i[edit update]

    def create
      occurrence = @pulse.current_occurrence || Time.zone.today

      beat = @pulse.beats_on(occurrence).find_by(creator_id: Current.user.id)
      if beat
        beat.record.revise(event: :updated, content: beat_params[:content], word_count: beat_params[:word_count])
        Mentions.deliver_for(beat.record)
      elsif beat_params[:content].present?
        record = Record.originate(
          Beat.new(content: beat_params[:content], word_count: beat_params[:word_count],
            asked_on: occurrence, creator: Current.user),
          parent: @record)
        Mentions.deliver_for(record)
      end

      redirect_to circle_pulse_path(@circle, @record, anchor: "beats")
    end

    def edit
    end

    def update
      @beat = @beat_record.revise(event: :updated, **beat_params.to_h.symbolize_keys)

      if @beat.errors.none?
        Mentions.deliver_for(@beat_record)
        redirect_to circle_pulse_path(@circle, @record, anchor: "beat_#{@beat_record.id}")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private
      def set_pulse
        @record = @circle.records.active.where(recordable_type: "Pulse").find(params[:pulse_id])
        @pulse = @record.recordable
      end

      # The member's own answer under this pulse; anyone else's is a 404 —
      # what's editable is nobody's business but the author's.
      def set_beat
        @beat_record = @circle.records.active.where(recordable_type: "Beat", parent_id: @record.id).find(params[:id])
        raise ActiveRecord::RecordNotFound unless @beat_record.editable_by?(Current.user)
        @beat = @beat_record.recordable
      end

      def beat_params
        params.expect(beat: [ :content, :word_count ])
      end
  end
end
