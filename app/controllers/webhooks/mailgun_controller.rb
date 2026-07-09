# Receives Mailgun event webhooks (delivered / opened / clicked / failed /
# complained / unsubscribed) and records them against the matching
# BroadcastDelivery, driving the broadcasts dashboard metrics.
#
# A machine endpoint: inherits ActionController::Base directly, so none of the
# app's browser/auth/forgery concerns apply. Authenticity is the Mailgun HMAC
# signature instead (verified against the webhook signing key). Unknown or
# unmatched events return 200 so Mailgun doesn't retry them forever.
class Webhooks::MailgunController < ActionController::Base
  def create
    return head(:unauthorized) unless verified?

    ingest
    head :ok
  end

  private
    def verified?
      signature = params[:signature]
      key = signing_key
      return false if signature.blank? || key.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", key, "#{signature[:timestamp]}#{signature[:token]}")
      ActiveSupport::SecurityUtils.secure_compare(expected, signature[:signature].to_s)
    end

    def ingest
      data = params["event-data"] || {}
      variables = data["user-variables"] || {}
      delivery = BroadcastDelivery.find_by(
        broadcast_id: variables["broadcast_id"], subscriber_id: variables["subscriber_id"])
      return unless delivery

      first_time = delivery.record_event!(data["event"])

      # A Mailgun-side unsubscribe should also drop them from our list (logged in
      # the consent trail like any other opt-out).
      if first_time && data["event"] == "unsubscribed"
        delivery.subscriber.unsubscribe!(source: "mailgun")
      end
    end

    def signing_key
      Rails.application.credentials.dig(:mailgun, :webhook_signing_key) || ENV["MAILGUN_WEBHOOK_SIGNING_KEY"]
    end
end
