# Receives Postmark event webhooks, verifies them, and translates each into a
# canonical DeliveryEvent — the Postmark adapter at the provider boundary.
# Everything downstream (milestones, suppression, subscriber status) reads only
# the canonical form; this controller is the last place Postmark's vocabulary
# exists.
#
# A machine endpoint: inherits ActionController::Base directly, so none of the
# app's browser/auth/forgery concerns apply. Postmark posts one JSON event per
# request and does not sign the payload, so authenticity is HTTP Basic Auth
# configured on the webhook itself (Postmark's "Custom headers and basic auth").
# Each event echoes the ids we set as Metadata on the outbound mail, which is how
# we route it back to the right delivery (Postmark ignores the SES message tags).
class Webhooks::PostmarkController < ActionController::Base
  # A machine endpoint with no session/cookies and no CSRF token — the app-wide
  # forgery protection would 422 every Postmark POST. Authenticity is the Basic
  # Auth credentials instead (authenticate below).
  skip_forgery_protection

  # Seam for tests: the expected [user, pass]. Nil in real environments → the
  # values come from encrypted credentials (postmark.webhook_user / _pass).
  cattr_accessor :basic_auth_credentials

  before_action :authenticate

  # Postmark RecordType → canonical event. Bounce fans out by Type below;
  # SubscriptionChange and anything unrecognized fall through to a no-op.
  EVENT_MAP = {
    "Delivery"      => "delivered",
    "Open"          => "opened",
    "Click"         => "clicked",
    "SpamComplaint" => "complaint"
  }.freeze

  def create
    ingest(JSON.parse(request.raw_post))
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private
    def authenticate
      user, pass = expected_credentials
      authenticate_or_request_with_http_basic("Postmark") do |u, p|
        user.present? && pass.present? &&
          ActiveSupport::SecurityUtils.secure_compare(u.to_s, user) &
          ActiveSupport::SecurityUtils.secure_compare(p.to_s, pass)
      end
    end

    def expected_credentials
      self.class.basic_auth_credentials ||
        [ Rails.application.credentials.dig(:postmark, :webhook_user),
          Rails.application.credentials.dig(:postmark, :webhook_pass) ]
    end

    def ingest(payload)
      event = canonical_event(payload)
      return unless event

      DeliveryEvent.ingest!(
        provider: "postmark",
        event: event,
        payload: payload,
        provider_message_id: payload["MessageID"],
        recipient: payload["Recipient"] || payload["Email"],
        occurred_at: timestamp(payload),
        delivery: find_delivery(payload["Metadata"] || {})
      )
    end

    def canonical_event(payload)
      payload["RecordType"] == "Bounce" ? bounce_event(payload) : EVENT_MAP[payload["RecordType"]]
    end

    # The bounce ladder, most-specific first. Blocked is an ISP/policy refusal —
    # about our reputation, not their address — so it's rejected, never a
    # bounce. SpamNotification is a spam-flagged bounce: a complaint in bounce
    # clothing. HardBounce (or Postmark deactivating the address, Inactive) is
    # permanent; everything else (SoftBounce, Transient, …) is transient.
    def bounce_event(payload)
      case payload["Type"]
      when "Blocked"          then "rejected"
      when "SpamNotification" then "complaint"
      when "HardBounce"       then "hard_bounce"
      else payload["Inactive"] ? "hard_bounce" : "soft_bounce"
      end
    end

    # Route by the ids Postmark echoed in Metadata: broadcasts stamp a
    # BroadcastDelivery, drip drops a DropDelivery. Both speak record_event! and
    # belong to a subscriber. An unmatched event still records (audit trail) —
    # it just has no delivery or subscriber to act on.
    def find_delivery(metadata)
      subscriber_id = metadata["subscriber_id"]
      if (broadcast_id = metadata["broadcast_id"])
        BroadcastDelivery.find_by(broadcast_id:, subscriber_id:)
      elsif (drop_record_id = metadata["drop_record_id"])
        DropDelivery.find_by(drop_record_id:, subscriber_id:)
      end
    end

    # The event's own timestamp, per RecordType (DeliveredAt on Delivery,
    # BouncedAt on Bounce/SpamComplaint, ReceivedAt on Open/Click).
    def timestamp(payload)
      value = payload["DeliveredAt"] || payload["BouncedAt"] || payload["ReceivedAt"]
      Time.iso8601(value) if value
    rescue ArgumentError
      nil
    end
end
