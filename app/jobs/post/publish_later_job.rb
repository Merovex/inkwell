# Publishes a scheduled post when its time arrives. No-ops if the post was
# trashed, published early, reverted, or rescheduled to a later time (each
# reschedule enqueues its own job; stale ones fail the guards).
class Post::PublishLaterJob < ApplicationJob
  # The scheduled record may have been deleted outright before its time came.
  discard_on ActiveJob::DeserializationError

  def perform(record)
    post = record.recordable
    return if record.trashed?
    return unless post.scheduled?
    return if post.published_at.future?

    post.publish
  end
end
