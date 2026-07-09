require "test_helper"

# Mailgun event webhooks → broadcast metrics. Authenticity is the Mailgun HMAC
# signature; events map to a BroadcastDelivery via the custom variables we stamp
# on each email.
class MailgunWebhookTest < ActionDispatch::IntegrationTest
  SIGNING_KEY = "test-signing-key"

  setup do
    ENV["MAILGUN_WEBHOOK_SIGNING_KEY"] = SIGNING_KEY
    @broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 1)
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    @delivery = @broadcast.deliveries.create!(subscriber: @subscriber, sent_at: Time.current)
  end

  teardown { ENV.delete("MAILGUN_WEBHOOK_SIGNING_KEY") }

  test "a signed delivered event stamps the delivery and bumps the counter" do
    post_event "delivered"

    assert_response :ok
    assert @delivery.reload.delivered_at
    assert_equal 1, @broadcast.reload.delivered_count
  end

  test "duplicate opens count once" do
    post_event "opened"
    post_event "opened"

    assert_equal 1, @broadcast.reload.opened_count
  end

  test "an unsubscribed event also drops the subscriber from the list" do
    post_event "unsubscribed"

    assert @subscriber.reload.unsubscribed?
    assert_equal 1, @broadcast.reload.unsubscribed_count
  end

  test "a bad signature is rejected and records nothing" do
    payload = event_payload("opened")
    payload[:signature][:signature] = "bogus"
    post "/webhooks/mailgun", params: payload, as: :json

    assert_response :unauthorized
    assert_equal 0, @broadcast.reload.opened_count
  end

  test "an event for an unknown delivery is a no-op 200" do
    post_event "opened", subscriber_id: 999_999

    assert_response :ok
    assert_equal 0, @broadcast.reload.opened_count
  end

  private
    def event_payload(event, broadcast_id: @broadcast.id, subscriber_id: @subscriber.id)
      timestamp = "1700000000"
      token = "abc123def456"
      signature = OpenSSL::HMAC.hexdigest("SHA256", SIGNING_KEY, "#{timestamp}#{token}")
      {
        signature: { timestamp: timestamp, token: token, signature: signature },
        "event-data": {
          event: event,
          recipient: @subscriber.email_address,
          "user-variables": { broadcast_id: broadcast_id.to_s, subscriber_id: subscriber_id.to_s }
        }
      }
    end

    def post_event(event, **overrides)
      post "/webhooks/mailgun", params: event_payload(event, **overrides), as: :json
    end
end
