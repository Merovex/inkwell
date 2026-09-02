# The Progress leaderboard — a sibling board view (the segmented control's
# "Progress"). Reads the circle's Pulse beats into the ledger and renders the
# shared board shell around the standings table.
module Circles
  class ProgressController < BaseController
    def show
      @ledger = Circle::Ledger.new(@circle)
      load_board_chrome
    end
  end
end
