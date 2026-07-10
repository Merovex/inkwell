# Newsletter emails to anonymous subscribers. `confirmation` is the double
# opt-in step: it carries the tokened confirm link that flips a pending
# subscriber to confirmed, plus a stable one-click unsubscribe link. From/site
# name come from Setting.current so the press's identity drives the mail.
class SubscriberMailer < ApplicationMailer
  # Newsletter stream → marketing configuration set (open/click tracking on).
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set)
  }

  def confirmation(subscriber, token)
    setting = Setting.current
    @site_name = setting.site_name
    @confirm_url = confirm_newsletter_url(token: token)
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe))

    options = { to: subscriber.email_address, subject: "Confirm your #{@site_name} subscription", from: marketing_from(setting) }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end

  # The one-time "still want these?" nudge sent to a cold subscriber before we
  # sunset them (ADR 0014). "Keep me subscribed" re-engages reliably (doesn't
  # depend on the SES open pixel); ignoring it leads to an automatic
  # unsubscribe after the grace window.
  def re_engagement(subscriber, token)
    setting = Setting.current
    @site_name = setting.site_name
    @keep_url = keep_newsletter_url(token: token)
    @unsubscribe_url = unsubscribe_newsletter_url(token: token)

    options = { to: subscriber.email_address, subject: "Still want emails from #{@site_name}?", from: marketing_from(setting) }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end
end
