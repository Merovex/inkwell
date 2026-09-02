# The bell is a doorbell, not an archive: read notifications older than 30
# days are deleted daily (config/recurring.yml). Unread ones wait — nothing
# vanishes before it's been seen.
class NotificationPruneJob < ApplicationJob
  RETENTION = 30.days

  def perform
    Notification.where(read_at: ..RETENTION.ago).delete_all
  end
end
