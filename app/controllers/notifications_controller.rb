# The bell's flyout shows the recent 15; this page is the whole 30-day window
# (NotificationPruneJob's retention) for when the glance isn't enough.
# Visiting counts as the deepest read, so it marks everything, same contract
# as opening the flyout.
class NotificationsController < ApplicationController
  def index
    @notifications = Current.user.notifications.order(created_at: :desc)
      .includes(actor: { avatar_attachment: :blob })
    Current.user.notifications.unread.update_all(read_at: Time.current)
  end

  def read_all
    Current.user.notifications.unread.update_all(read_at: Time.current)
    head :no_content
  end
end
