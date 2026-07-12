require "net/http"

# Receives Amazon SES event notifications relayed through SNS (Delivery / Open /
# Click / Bounce / Complaint) and records them against the matching
# BroadcastDelivery, driving the /admin/broadcasts dashboard — the SES-side
# counterpart to Webhooks::MailgunController (ADR 0015 Phase 2).
#
# A machine endpoint: inherits ActionController::Base directly, so none of the
# app's browser/auth/forgery concerns apply. Authenticity is the SNS message
# signature (cert-based, Aws::SNS::MessageVerifier) over the raw body. SNS posts
# text/plain, so we parse request.raw_post ourselves rather than through params.
class Webhooks::SesController < ActionController::Base
  # Seam for tests to inject a fake verifier (SNS signatures are RSA/cert-based
  # and can't be reproduced offline). Nil in every real environment → the actual
  # Aws::SNS::MessageVerifier is used.
  cattr_accessor :message_verifier

  # SES event type → the internal event name BroadcastDelivery#record_event!
  # already understands (shared with the Mailgun path, dropped in Phase 3).
  # Bounce is handled separately (permanent vs transient); Send/Delivery-Delay
  # carry no signal for us and fall through to a no-op.
  EVENT_MAP = {
    "Delivery"         => "delivered",
    "Open"             => "opened",
    "Click"            => "clicked",
    "Complaint"        => "complained",
    "Reject"           => "bounced",
    "RenderingFailure" => "bounced"
  }.freeze

  def create
    body = request.raw_post
    return head(:unauthorized) unless verified?(body)

    message = JSON.parse(body)
    case message["Type"]
    when "SubscriptionConfirmation"
      confirm_subscription(message)
    when "Notification"
      ingest(JSON.parse(message["Message"].to_s))
    end

    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private
    def verified?(body)
      (message_verifier || Aws::SNS::MessageVerifier.new).authentic?(body)
    rescue StandardError
      false
    end

    # SNS one-time handshake: fetching the SubscribeURL activates the
    # subscription. The signature over the whole message (SubscribeURL included)
    # is already verified, but keep the fetch to AWS's own host as belt-and-braces.
    def confirm_subscription(message)
      url = message["SubscribeURL"].to_s
      uri = URI(url)
      Net::HTTP.get(uri) if uri.host&.match?(/\Asns\.[\w-]+\.amazonaws\.com\z/)
    end

    def ingest(event)
      tags = event.dig("mail", "tags") || {}
      delivery = BroadcastDelivery.find_by(
        broadcast_id: tag(tags, "broadcast_id"), subscriber_id: tag(tags, "subscriber_id"))
      return unless delivery

      internal = internal_event(event)
      return unless internal

      first_time = delivery.record_event!(internal)

      # An SES complaint is a "mark as spam" — drop them from the list (logged in
      # the consent trail like any other opt-out). SES has no unsubscribe event.
      if first_time && internal == "complained"
        delivery.subscriber.unsubscribe!(source: "ses")
      end
    end

    # Permanent bounces stamp bounced_at; transient bounces (mailbox full, etc.)
    # are temporary — SES keeps retrying, so don't hold them against the recipient.
    # Everything else comes from the static EVENT_MAP.
    def internal_event(event)
      type = event["eventType"] || event["notificationType"]
      if type == "Bounce"
        event.dig("bounce", "bounceType") == "Permanent" ? "bounced" : nil
      else
        EVENT_MAP[type]
      end
    end

    # SES message tags arrive as arrays of strings ({ "broadcast_id" => ["5"] }).
    def tag(tags, name)
      Array(tags[name]).first
    end
end
