# Fans a broadcast out to every confirmed subscriber, one email each. Resumable
# and idempotent: each recipient gets a BroadcastDelivery row (unique per
# subscriber), and anyone already stamped sent_at is skipped — so a retried or
# half-finished job never double-mails. Stamps the broadcast when done.
class PostBroadcastJob < ApplicationJob
  # A scheduled broadcast may have been canceled (row deleted) before its time
  # came — the wait_until job then just no-ops, like Record::PublishLaterJob.
  discard_on ActiveJob::DeserializationError

  def perform(broadcast)
    Subscriber.confirmed.find_each do |subscriber|
      delivery = broadcast.deliveries.create_or_find_by!(subscriber: subscriber)
      next if delivery.sent_at

      PostBroadcastMailer.issue(broadcast, subscriber).deliver_now
      delivery.update!(sent_at: Time.current)
    end

    broadcast.update!(sent_at: Time.current,
      recipients_count: broadcast.deliveries.where.not(sent_at: nil).count)
  end
end
