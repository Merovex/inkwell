# A circle's Pulse check (Pulse). The owner sets it up and edits it; members
# subscribe/unsubscribe themselves and answer with a Beat. The question and
# schedule are versioned (Pulse is a recordable), so edits land as history.
module Circles
  class PulsesController < BaseController
    include PulseDetail

    before_action :set_pulse, only: %i[show edit update destroy]
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
        @pulse.subscribe(@circle.members)
        redirect_to circle_pulse_path(@circle, @pulse.record), notice: "Pulse check set up."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      # ?day= deep-links a specific ask-day (the wall's pulse cards) — we show
      # the WEEK that contains it; past weeks are read-only history.
      load_pulse_detail(@record, week_of: requested_day || Time.zone.today)
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

    private
      def set_pulse
        @record = @circle.records.active.where(recordable_type: "Pulse").find(params[:id])
        @pulse = @record.recordable
      end

      # ?day= parsed defensively: garbage reads as no request, not a 500.
      def requested_day
        Date.iso8601(params[:day].to_s)
      rescue Date::Error
        nil
      end

      # The composer submits selected weekdays as an array; fold them into the
      # days_of_week bitmask. Monthly is a single "first <weekday>", so clamp it
      # to one day even if a non-JS submit sent more (isolate the lowest bit).
      def pulse_params
        permitted = params.expect(pulse: [ :question, :description, :cadence, :ask_at_minutes, :active, { weekdays: [] } ])
        mask = Array(permitted.delete(:weekdays)).map(&:to_i).sum { |wday| 1 << wday }
        mask &= -mask if permitted[:cadence] == "monthly" && mask.positive?
        permitted[:days_of_week] = mask
        permitted
      end
  end
end
