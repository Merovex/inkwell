# One email per person rolling up their unread, not-yet-emailed notifications
# of the given kinds. Two cadences share this job (config/recurring.yml):
# every 4 hours for the default kinds, once a day for the calm ones
# (EMAILED_DAILY — thread replies shouldn't bug anyone). Anything read in-app
# before the digest runs is skipped for good: the bell beat us to it.
class NotificationDigestJob < ApplicationJob
  def perform(kinds = Notification::EMAILED - Notification::EMAILED_DAILY)
    pending = Notification.unread.where(emailed_at: nil, kind: kinds)

    User.where(id: pending.select(:user_id).distinct).find_each do |user|
      batch = user.notifications.unread.where(emailed_at: nil, kind: kinds)
        .order(:created_at).to_a
      next if batch.empty?

      NotificationMailer.digest(user, batch).deliver_later
      Notification.where(id: batch.map(&:id)).update_all(emailed_at: Time.current)
    end

    # Read before we got here — mark covered so the scope stays small. Only
    # email-worthy kinds: emailed_at should keep meaning what it says.
    Notification.where.not(read_at: nil)
      .where(emailed_at: nil, kind: Notification::EMAILED).update_all(emailed_at: Time.current)
  end
end
