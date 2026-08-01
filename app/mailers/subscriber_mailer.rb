# Newsletter emails to anonymous subscribers. `confirmation` is the double
# opt-in step: it carries the tokened confirm link that flips a pending
# subscriber to confirmed, plus a stable one-click unsubscribe link. From/site
# name come from the account's Site so the press's identity drives the mail.
class SubscriberMailer < ApplicationMailer
  # These are transactional in nature — the confirm and "keep subscribed" links
  # are critical actions, so they must NOT be click-rewritten. Route through the
  # transactional config set (no open/click tracking). The From still comes from
  # the news.merovex.press identity, so newsletter reputation stays isolated;
  # only the broadcast issues (PostBroadcastMailer) use the tracked marketing set.
  # Transactional on Postmark — the confirm and "keep subscribed" links ride the
  # default `outbound` stream, never the bulk Broadcast stream, so they're not
  # click-rewritten. (SES config set kept alongside for an easy revert.)
  default message_stream: "outbound",
    delivery_method_options: {
      configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set)
    }

  def confirmation(subscriber, token)
    setting = subscriber.account.site
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
    setting = subscriber.account.site
    @site_name = setting.site_name
    @keep_url = keep_newsletter_url(token: token)
    @unsubscribe_url = unsubscribe_newsletter_url(token: token)

    options = { to: subscriber.email_address, subject: "Still want emails from #{@site_name}?", from: marketing_from(setting) }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end
end
