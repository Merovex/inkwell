# The Pulse checks board view (the segmented control's "Pulse Checks"): the
# circle's primary check in full — its composer, this week's answers, and the
# earlier weeks — shared with the standalone pulse page. Any other checks list
# beneath it. Renders inside the board shell.
module Circles
  class ChecksController < BaseController
    include PulseDetail

    def index
      @pulses = @circle.pulses.to_a
      # The primary check to detail: the live one, or any check if all paused.
      @pulse = @circle.pulse || @pulses.first
      load_pulse_detail(@pulse.record) if @pulse
      @other_checks = @pulses.reject { |p| @pulse && p.record_id == @pulse.record_id }
      load_board_chrome
    end
  end
end
