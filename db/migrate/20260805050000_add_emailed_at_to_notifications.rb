# Notification email goes out in 4-hour batches (NotificationDigestJob), not
# per-event: emailed_at marks what a digest has covered. Nothing notification-
# shaped is time-sensitive; batching keeps inboxes calm.
class AddEmailedAtToNotifications < ActiveRecord::Migration[8.2]
  def change
    add_column :notifications, :emailed_at, :datetime
  end
end
