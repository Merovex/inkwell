# Emails one published post to one subscriber — the newsletter issue. The post's
# public blog page doubles as the "view in browser" archive (HEY World). Carries
# the subscriber's stable unsubscribe token both in the body and as a
# List-Unsubscribe header (RFC 8058 one-click) for deliverability. Sends from
# the site's own broadcast address (BYOD sending domain or the shared lane —
# Account#broadcast_from), stamped into the site's SES tenant; the site's name
# + contact address ride along as the display label and Reply-To.
class PostBroadcastMailer < ApplicationMailer
  def issue(broadcast, subscriber)
    @post = broadcast.post
    account = broadcast.record.bucket
    setting = account.site
    @site_name = setting.site_name
    # Reader-facing links live on the press's public address (custom domain or
    # apex slug path), never the app host.
    url_options = public_url_options(account)
    @web_url = blog_post_url(broadcast.record.to_slug, **url_options)
    # Carry the broadcast so an unsubscribe from *this* issue attributes to it on
    # the dashboard (metrics only — see SubscriptionsController#unsubscribe).
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe), broadcast: broadcast.id, **url_options)

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    options = {
      to: subscriber.email_address,
      subject: @post.title,
      from: broadcast_from(account),
      # Bulk mail rides Postmark's Broadcast stream (required — Postmark won't
      # send bulk on the transactional stream).
      message_stream: broadcast_stream,
      # SES echoes these message tags on every event, so Webhooks::SesController
      # maps a delivered/opened/clicked/bounced event back to this recipient's
      # BroadcastDelivery. The marketing config set turns on open/click tracking.
      # Tag values are alphanumeric-only, so the integer ids go as strings.
      # site_tenant_options attributes the send to the site's own SES tenant.
      delivery_method_options: {
        configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
        email_tags: [
          { name: "broadcast_id", value: broadcast.id.to_s },
          { name: "subscriber_id", value: subscriber.id.to_s }
        ],
        **site_tenant_options(account)
      }
    }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    message = mail(options)

    # Postmark open/link tracking, plus the ids echoed back on every event so
    # Webhooks::PostmarkController can map delivered/opened/clicked/bounced/
    # complained to this delivery. Postmark ignores the SES email_tags above, so
    # Metadata is the mapping key under Postmark. Link tracking rewrites in-body
    # links but never the List-Unsubscribe header, so one-click opt-out stays clean.
    message.track_opens = true
    message.track_links = :html_and_text
    message.metadata = { "broadcast_id" => broadcast.id.to_s, "subscriber_id" => subscriber.id.to_s }
    message
  end
end
