# A member's own seat at a circle's Pulse check: POST subscribes them (they'll
# be asked next occurrence), DELETE opts them out. Always the current member's
# row — nobody manages anyone else's subscription.
module Circles
  module Pulses
    class SubscriptionsController < BaseController
      before_action :set_pulse

      def create
        PulseSubscription.create(pulse_record: @record, user: Current.user)
        redirect_to circle_pulse_path(@circle, @record), notice: "You're in — you'll be asked next time."
      end

      def destroy
        @pulse.subscriptions.where(user: Current.user).destroy_all
        redirect_to circle_pulse_path(@circle, @record), notice: "You've opted out of this Pulse check."
      end

      private
        def set_pulse
          @record = @circle.records.active.where(recordable_type: "Pulse").find(params[:pulse_id])
          @pulse = @record.recordable
        end
    end
  end
end
