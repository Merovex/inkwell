# A peer poke — nudge a circle member who still owes an answer this week. Any
# member may nudge; it rings the target's bell (a "nudged" notification) and
# lands back on the checks board.
module Circles
  module Pulses
    class NudgesController < BaseController
      before_action -> { authorize! @circle, to: :post }

      def create
        record = @circle.records.active.where(recordable_type: "Pulse").find(params[:pulse_id])
        member = @circle.members.find(params[:member_id])
        Notification.deliver(record, to: member, kind: "nudged")
        redirect_to circle_checks_path(@circle), notice: "Nudged #{member.display_name}."
      end
    end
  end
end
