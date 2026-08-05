# Every 4 hours (config/recurring.yml): one email per person rolling up their
# unread, not-yet-emailed, email-worthy notifications. Nothing notification-
# shaped is time-sensitive — batching keeps email overhead low and inboxes
# calm. Anything read in-app before the digest runs is skipped for good: the
# bell beat us to it.
class NotificationDigestJob < ApplicationJob
  def perform
    pending = Notification.unread.where(emailed_at: nil, kind: Notification::EMAILED)

    User.where(id: pending.select(:user_id).distinct).find_each do |user|
      batch = user.notifications.unread.where(emailed_at: nil, kind: Notification::EMAILED)
        .order(:created_at).to_a
      next if batch.empty?

      NotificationMailer.digest(user, batch).deliver_later
      Notification.where(id: batch.map(&:id)).update_all(emailed_at: Time.current)
    end

    # Read before we got here — mark covered so the scope stays small.
    Notification.where.not(read_at: nil).where(emailed_at: nil).update_all(emailed_at: Time.current)
  end
end
