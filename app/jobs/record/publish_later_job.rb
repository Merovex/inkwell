# Publishes scheduled content (a post, a message) when its time arrives.
# No-ops if it was trashed, published early, reverted, or rescheduled to a
# later time (each reschedule enqueues its own job; stale ones fail the
# guards).
class Record::PublishLaterJob < ApplicationJob
  # The scheduled record may have been deleted outright before its time came.
  discard_on ActiveJob::DeserializationError

  def perform(record)
    publishable = record.recordable
    return if record.trashed?
    return unless publishable.scheduled?
    return if publishable.published_at.future?

    publishable.publish
  end
end
