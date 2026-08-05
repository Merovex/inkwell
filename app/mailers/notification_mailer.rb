# Emails for immediate-class notifications (Notification::EMAILED) — one
# method per kind. Transactional: the app identity, links pinned to the app
# host (app_url_options).
class NotificationMailer < ApplicationMailer
  def invited(notification)
    @invitation = notification.source
    @circle = @invitation.circle
    @inviter = @invitation.inviter
    @circles_url = circles_url(**app_url_options)

    mail to: notification.user.email_address,
         subject: "#{@inviter.display_name} invited you to #{@circle.name} on Inkwell"
  end
end
