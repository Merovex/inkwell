# A circle's Pulse check (Pulse). The owner sets it up and edits it; members
# subscribe/unsubscribe themselves and answer with a Beat. The question and
# schedule are versioned (Pulse is a recordable), so edits land as history.
module Circles
  class PulsesController < BaseController
    layout "application"

    before_action :set_pulse, only: %i[show edit update destroy subscribe unsubscribe]
    # Only the circle owner manages the Pulse check itself.
    before_action -> { authorize! @circle, to: :manage }, only: %i[new create edit update destroy]

    def new
      @pulse = Pulse.new(cadence: "weekly", days_of_week: 1 << 1, ask_at_minutes: 990) # Mondays, 4:30pm
    end

    def create
      @pulse = Pulse.new(pulse_params.merge(event: :created))

      if @pulse.valid?
        Record.originate(@pulse)
        # Everyone's in by default; each member can opt out later.
        @circle.members.find_each { |member| PulseSubscription.create(pulse_record: @pulse.record, user: member) }
        redirect_to circle_pulse_path(@circle, @pulse.record), notice: "Pulse check set up."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @occurrence = @pulse.current_occurrence || Time.zone.today
      @beats = @pulse.beats_on(@occurrence)
      @my_beat = @beats.find_by(creator_id: Current.user.id)
    end

    def edit
    end

    def update
      @pulse = @record.revise(event: :updated, **pulse_params.to_h.symbolize_keys)

      if @pulse.errors.none?
        redirect_to circle_pulse_path(@circle, @record), notice: "Pulse check updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @record.trash
      redirect_to circle_path(@circle), notice: "Pulse check removed."
    end

    def subscribe
      PulseSubscription.create(pulse_record: @record, user: Current.user)
      redirect_to circle_pulse_path(@circle, @record), notice: "You're in — you'll be asked next time."
    end

    def unsubscribe
      @pulse.subscriptions.where(user: Current.user).destroy_all
      redirect_to circle_pulse_path(@circle, @record), notice: "You've opted out of this Pulse check."
    end

    private
      def set_pulse
        @record = @circle.records.active.where(recordable_type: "Pulse").find(params[:id])
        @pulse = @record.recordable
      end

      # The composer submits selected weekdays as an array; fold them into the
      # days_of_week bitmask. Monthly is a single "first <weekday>", so clamp it
      # to one day even if a non-JS submit sent more (isolate the lowest bit).
      def pulse_params
        permitted = params.expect(pulse: [ :question, :cadence, :ask_at_minutes, :active, { weekdays: [] } ])
        mask = Array(permitted.delete(:weekdays)).map(&:to_i).sum { |wday| 1 << wday }
        mask &= -mask if permitted[:cadence] == "monthly" && mask.positive?
        permitted[:days_of_week] = mask
        permitted
      end
  end
end
