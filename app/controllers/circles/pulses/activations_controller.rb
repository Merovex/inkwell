# Pause/resume a Pulse check — the check's active state as a resource. POST
# resumes (active), DELETE pauses. Each flip is a tracked version (like any
# pulse edit). Owner-only, and it lands back on the checks index.
module Circles
  module Pulses
    class ActivationsController < BaseController
      before_action :set_pulse
      before_action -> { authorize! @circle, to: :manage }

      def create
        @record.revise(event: :updated, active: true)
        redirect_to circle_checks_path(@circle), notice: "Pulse check resumed."
      end

      def destroy
        @record.revise(event: :updated, active: false)
        redirect_to circle_checks_path(@circle), notice: "Pulse check paused."
      end

      private
        def set_pulse
          @record = @circle.records.active.where(recordable_type: "Pulse").find(params[:pulse_id])
        end
    end
  end
end
