# Emails one published post to one subscriber — the newsletter issue. The post's
# public blog page doubles as the "view in browser" archive (HEY World). Carries
# the subscriber's stable unsubscribe token both in the body and as a
# List-Unsubscribe header (RFC 8058 one-click) for deliverability. Sends from the
# news.merovex.press identity (aligned DKIM); the press's name + contact address
# ride along as the display label and Reply-To.
class PostBroadcastMailer < ApplicationMailer
  def issue(broadcast, subscriber)
    @post = broadcast.post
    setting = Setting.current
    @site_name = setting.site_name
    @web_url = blog_post_url(broadcast.record.to_slug)
    # Carry the broadcast so an unsubscribe from *this* issue attributes to it on
    # the dashboard (metrics only — see SubscriptionsController#unsubscribe).
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe), broadcast: broadcast.id)

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    options = {
      to: subscriber.email_address,
      subject: @post.title,
      from: marketing_from(setting),
      # SES echoes these message tags on every event, so Webhooks::SesController
      # maps a delivered/opened/clicked/bounced event back to this recipient's
      # BroadcastDelivery. The marketing config set turns on open/click tracking.
      # Tag values are alphanumeric-only, so the integer ids go as strings.
      delivery_method_options: {
        configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
        email_tags: [
          { name: "broadcast_id", value: broadcast.id.to_s },
          { name: "subscriber_id", value: subscriber.id.to_s }
        ]
      }
    }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    mail(options)
  end
end
