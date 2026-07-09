# Newsletter emails to anonymous subscribers. `confirmation` is the double
# opt-in step: it carries the tokened confirm link that flips a pending
# subscriber to confirmed, plus a stable one-click unsubscribe link. From/site
# name come from Setting.current so the press's identity drives the mail.
class SubscriberMailer < ApplicationMailer
  def confirmation(subscriber, token)
    setting = Setting.current
    @site_name = setting.site_name
    @confirm_url = confirm_newsletter_url(token: token)
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe))

    options = { to: subscriber.email_address, subject: "Confirm your #{@site_name} subscription" }
    options[:from] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end
end
