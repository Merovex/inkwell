# Advance one subscriber's drip run: send any Drops now due (or skip them if the
# subscriber has since unsubscribed). Enqueued on confirmation for the immediate
# day-0 Drop, and per active stream by the daily DripTickJob. The work is
# idempotent (Stream#advance! guards on the delivery rows), so a retry is safe.
class DripAdvanceJob < ApplicationJob
  discard_on ActiveJob::DeserializationError  # stream/subscriber gone → nothing to do

  def perform(stream)
    stream.advance!
  end
end
