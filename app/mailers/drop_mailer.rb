# Sends one Drop (a drip-campaign email) to one subscriber. The body is the
# Drop's Lexxy rich text, rendered like a broadcast issue. Sends from the
# news.merovex.press marketing identity with the press name as the display label
# and a one-click unsubscribe, so a drip is indistinguishable from any newsletter
# for deliverability. Routes through the marketing config set (open/click
# tracking on) with message tags, so SES events flow back to this DropDelivery
# via Webhooks::SesController; the List-Unsubscribe header is never rewritten, so
# one-click opt-out stays clean.
class DropMailer < ApplicationMailer
  def step(stream, drop)
    @drop = drop
    subscriber = stream.subscriber
    setting = Setting.current
    @site_name = setting.site_name
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe))

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    options = {
      to: subscriber.email_address,
      subject: drop.subject,
      from: marketing_from(setting),
      delivery_method_options: {
        configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
        email_tags: [
          { name: "drop_record_id", value: drop.record_id.to_s },
          { name: "subscriber_id", value: subscriber.id.to_s }
        ]
      }
    }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end
end
