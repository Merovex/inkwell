# The 4-hour notification digest (NotificationDigestJob): one email rolling
# up a person's unread, email-worthy notifications. Transactional — the app
# identity, links pinned to the app host (app_url_options). A single item
# borrows its own sentence as the subject.
class NotificationMailer < ApplicationMailer
  def digest(user, notifications)
    @notifications = notifications
    @base_url = root_url(**app_url_options).chomp("/")
    @notifications_url = "#{@base_url}/notifications"

    subject = notifications.one? ? notifications.first.title
                                 : "#{notifications.size} new notifications on Inkwell"
    mail to: user.email_address, subject: subject
  end
end
