# The 4-hour notification digest (NotificationDigestJob): one email rolling
# up a person's unread, email-worthy notifications. User bulk (stream 2,
# docs/email-architecture.md): platform voice, never the verification
# identity. Links pinned to the app host (app_url_options). A single item
# borrows its own sentence as the subject.
class NotificationMailer < ApplicationMailer
  # Bulk config set: complaint/bounce events flow like the newsletter's. The
  # platform-circles tenant stamp isolates this lane's reputation from auth
  # mail and from every site's newsletter (docs/ses-tenants.md).
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
    tenant_name: "platform-circles"
  }

  def digest(user, notifications)
    @notifications = notifications
    @base_url = root_url(**app_url_options).chomp("/")
    @notifications_url = "#{@base_url}/notifications"

    subject = notifications.one? ? notifications.first.title
                                 : "#{notifications.size} new notifications on Kindred Quill"
    mail to: user.email_address, from: platform_bulk_from, subject: subject
  end
end
