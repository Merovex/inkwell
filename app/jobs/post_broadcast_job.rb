# Fans a broadcast out to every sendable (confirmed, non-seed) subscriber, one
# email each — seed inboxes expire and hard-bounce, so they only ever get the
# confirmation email. Resumable
# and idempotent: each recipient gets a BroadcastDelivery row (unique per
# subscriber), and anyone already stamped sent_at is skipped — so a retried or
# half-finished job never double-mails. Stamps the broadcast when done.
class PostBroadcastJob < ApplicationJob
  # A scheduled broadcast may have been canceled (row deleted) before its time
  # came — the wait_until job then just no-ops, like Record::PublishLaterJob.
  discard_on ActiveJob::DeserializationError

  def perform(broadcast)
    broadcast.record.bucket.subscribers.sendable.find_each do |subscriber|
      delivery = broadcast.deliveries.create_or_find_by!(subscriber: subscriber)
      next if delivery.sent_at

      message = PostBroadcastMailer.issue(broadcast, subscriber).deliver_now
      # The dispatch stamp (which ESP + its message id) is what lets a later
      # bounce or complaint be attributed to this exact send.
      delivery.update!(sent_at: Time.current, **DeliveryEvent.dispatch_stamp(message))
    end

    broadcast.update!(sent_at: Time.current,
      recipients_count: broadcast.deliveries.where.not(sent_at: nil).count)
  end
end
