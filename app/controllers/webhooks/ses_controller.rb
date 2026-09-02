require "net/http"

# Receives Amazon SES event notifications relayed through SNS, verifies them,
# and translates each into a canonical DeliveryEvent — the SES adapter at the
# provider boundary, counterpart to Webhooks::PostmarkController. Everything
# downstream reads only the canonical form; this controller is the last place
# SES's vocabulary exists.
#
# A machine endpoint: inherits ActionController::Base directly, so none of the
# app's browser/auth/forgery concerns apply. Authenticity is the SNS message
# signature (cert-based, Aws::SNS::MessageVerifier) over the raw body. SNS posts
# text/plain, so we parse request.raw_post ourselves rather than through params.
class Webhooks::SesController < ActionController::Base
  # A machine endpoint with no session/cookies: SNS posts a raw JSON body with no
  # CSRF token, so the app-wide forgery protection (on by default via
  # load_defaults) would 422 every SNS delivery — including the subscription
  # handshake. Authenticity is the SNS signature instead (verified? below).
  skip_forgery_protection

  # Seam for tests to inject a fake verifier (SNS signatures are RSA/cert-based
  # and can't be reproduced offline). Nil in every real environment → the actual
  # Aws::SNS::MessageVerifier is used.
  cattr_accessor :message_verifier

  # SES event type → canonical event. Bounce fans out by bounceType below.
  # Reject is SES refusing the send (virus scan, etc.) and RenderingFailure is
  # our own template blowing up — neither reached a mailbox, neither is the
  # recipient's fault, so both are rejected, never bounces. Send/DeliveryDelay
  # carry no signal for us and fall through to a no-op.
  EVENT_MAP = {
    "Delivery"         => "delivered",
    "Open"             => "opened",
    "Click"            => "clicked",
    "Complaint"        => "complaint",
    "Reject"           => "rejected",
    "RenderingFailure" => "rejected"
  }.freeze

  # A Permanent bounce with these subtypes never left AWS: the address was
  # already on the account-level suppression list, so it says nothing new
  # about the mailbox — canonical `suppressed`, and it must not suppress the
  # subscriber (our database is authoritative, not AWS's list).
  SUPPRESSION_SUBTYPES = %w[ Suppressed OnAccountSuppressionList ].freeze

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
      canonical = canonical_event(event)
      return unless canonical

      DeliveryEvent.ingest!(
        provider: "ses",
        event: canonical,
        payload: event,
        provider_message_id: event.dig("mail", "messageId"),
        recipient: Array(event.dig("mail", "destination")).first,
        occurred_at: timestamp(event),
        delivery: find_delivery(event.dig("mail", "tags") || {})
      )
    end

    # Permanent splits into suppressed (never sent, see SUPPRESSION_SUBTYPES)
    # and a true hard bounce; Transient/Undetermined are soft — SES keeps
    # retrying, and the streak threshold (DeliveryEvent) decides when enough
    # is enough.
    def canonical_event(event)
      type = event["eventType"] || event["notificationType"]
      return EVENT_MAP[type] unless type == "Bounce"

      if event.dig("bounce", "bounceType") == "Permanent"
        event.dig("bounce", "bounceSubType").in?(SUPPRESSION_SUBTYPES) ? "suppressed" : "hard_bounce"
      else
        "soft_bounce"
      end
    end

    # Route by the id tag SES echoed: broadcasts stamp a BroadcastDelivery, drip
    # drops a DropDelivery. Both speak record_event! and belong to a subscriber.
    # An unmatched event still records (audit trail) — it just has no delivery
    # or subscriber to act on.
    def find_delivery(tags)
      subscriber_id = tag(tags, "subscriber_id")
      if (broadcast_id = tag(tags, "broadcast_id"))
        BroadcastDelivery.find_by(broadcast_id:, subscriber_id:)
      elsif (drop_record_id = tag(tags, "drop_record_id"))
        DropDelivery.find_by(drop_record_id:, subscriber_id:)
      end
    end

    # SES message tags arrive as arrays of strings ({ "broadcast_id" => ["5"] }).
    def tag(tags, name)
      Array(tags[name]).first
    end

    # The event object's own timestamp, falling back to the send time.
    def timestamp(event)
      value = %w[ delivery bounce complaint open click ].lazy
        .filter_map { |key| event.dig(key, "timestamp") }.first || event.dig("mail", "timestamp")
      Time.iso8601(value) if value
    rescue ArgumentError
      nil
    end
end
