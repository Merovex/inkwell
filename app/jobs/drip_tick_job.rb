# Daily drip heartbeat (config/recurring.yml): fan out one DripAdvanceJob per
# active stream so each subscriber's next due Drop goes out. Day-0 Drops already
# fired on confirmation; this catches every later Drop as its day arrives.
# Idempotent — advancing a stream with nothing due is a no-op.
class DripTickJob < ApplicationJob
  def perform
    Stream.active.find_each { |stream| DripAdvanceJob.perform_later(stream) }
  end
end
