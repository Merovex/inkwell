# Sends one Drop (a drip-campaign email) to one subscriber. The body is the
# Drop's Lexxy rich text, rendered like a broadcast issue. Sends from the
# news.merovex.press marketing identity with the press name as the display label
# and a one-click unsubscribe, so a drip is indistinguishable from any newsletter
# for deliverability. Routes through the transactional config set — the
# unsubscribe link must stay clickable, and onboarding mail isn't open-tracked.
class DropMailer < ApplicationMailer
  default delivery_method_options: {
    configuration_set_name: Rails.application.credentials.dig(:ses, :transactional_config_set)
  }

  def step(stream, drop)
    @drop = drop
    subscriber = stream.subscriber
    setting = Setting.current
    @site_name = setting.site_name
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe))

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    options = { to: subscriber.email_address, subject: drop.subject, from: marketing_from(setting) }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end
end
