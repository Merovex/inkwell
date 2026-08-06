# Sends one Drop (a drip-campaign email) to one subscriber. The body is the
# Drop's Lexxy rich text, rendered like a broadcast issue. Sends from the
# site's own broadcast address (Account#broadcast_from) with the site name as
# the display label and a one-click unsubscribe, so a drip is indistinguishable
# from any newsletter for deliverability. Routes through the marketing config set (open/click
# tracking on) with message tags, so SES events flow back to this DropDelivery
# via Webhooks::SesController; the List-Unsubscribe header is never rewritten, so
# one-click opt-out stays clean.
class DropMailer < ApplicationMailer
  def step(stream, drop)
    @drop = drop
    subscriber = stream.subscriber
    setting = subscriber.account.site
    @site_name = setting.site_name
    @unsubscribe_url = unsubscribe_newsletter_url(token: subscriber.generate_token_for(:unsubscribe),
      **public_url_options(subscriber.account))

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    options = {
      to: subscriber.email_address,
      subject: drop.subject,
      from: broadcast_from(subscriber.account),
      # Bulk mail rides Postmark's Broadcast stream (required — Postmark won't
      # send bulk on the transactional stream).
      message_stream: broadcast_stream,
      # site_tenant_options attributes the send to the site's own SES tenant.
      delivery_method_options: {
        configuration_set_name: Rails.application.credentials.dig(:ses, :marketing_config_set),
        email_tags: [
          { name: "drop_record_id", value: drop.record_id.to_s },
          { name: "subscriber_id", value: subscriber.id.to_s }
        ],
        **site_tenant_options(subscriber.account)
      }
    }
    options[:reply_to] = setting.contact_email if setting.contact_email.present?
    message = mail(options)

    # Postmark open/link tracking, plus the ids echoed back on every event so
    # Webhooks::PostmarkController can map the event to this DropDelivery. Postmark
    # ignores the SES email_tags above, so Metadata is the mapping key here. Link
    # tracking never touches the List-Unsubscribe header, so one-click stays clean.
    message.track_opens = true
    message.track_links = :html_and_text
    message.metadata = { "drop_record_id" => drop.record_id.to_s, "subscriber_id" => subscriber.id.to_s }
    message
  end
end
