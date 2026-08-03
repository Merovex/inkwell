# Receives Postmark event webhooks (Delivery / Open / Click / Bounce /
# SpamComplaint) and records them against the matching BroadcastDelivery or
# DropDelivery, driving the /admin/broadcasts dashboard — the Postmark-side
# counterpart to Webhooks::SesController.
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

  # Postmark RecordType → the internal event name the delivery models understand.
  # Bounce and SpamComplaint are handled separately; Delivery/Open/Click map here.
  EVENT_MAP = {
    "Delivery" => "delivered",
    "Open"     => "opened",
    "Click"    => "clicked"
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

    def ingest(event)
      delivery = find_delivery(event["Metadata"] || {})
      return unless delivery

      internal = internal_event(event)
      return unless internal

      first_time = delivery.record_event!(internal)

      # A spam complaint is a "mark as spam" — drop them from the list, logged in
      # the consent trail like any other opt-out. (Postmark has no unsubscribe
      # event on these streams; suppression-list changes arrive as SubscriptionChange.)
      if first_time && internal == "complained"
        delivery.subscriber.unsubscribe!(source: "postmark")
      end
    end

    # Route by the ids Postmark echoed in Metadata: broadcasts stamp a
    # BroadcastDelivery, drip drops a DropDelivery. Both speak record_event! and
    # belong to a subscriber.
    def find_delivery(metadata)
      subscriber_id = metadata["subscriber_id"]
      if (broadcast_id = metadata["broadcast_id"])
        BroadcastDelivery.find_by(broadcast_id:, subscriber_id:)
      elsif (drop_record_id = metadata["drop_record_id"])
        DropDelivery.find_by(drop_record_id:, subscriber_id:)
      end
    end

    # Only hard bounces stamp bounced_at; soft bounces are transient (Postmark
    # keeps retrying), so don't hold them against the recipient. SpamComplaint is
    # its own RecordType → "complained". Everything else comes from EVENT_MAP.
    def internal_event(event)
      case event["RecordType"]
      when "Bounce"        then hard_bounce?(event) ? "bounced" : nil
      when "SpamComplaint" then "complained"
      else EVENT_MAP[event["RecordType"]]
      end
    end

    # Postmark deactivates the address (Inactive) on a permanent failure; its
    # Type is "HardBounce" for a true hard bounce. Either signals permanence.
    def hard_bounce?(event)
      event["Type"] == "HardBounce" || event["Inactive"] == true
    end
end
