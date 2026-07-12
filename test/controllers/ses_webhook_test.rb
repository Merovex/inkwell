require "test_helper"

# SES event notifications relayed via SNS → broadcast metrics. Authenticity is
# the SNS signature (a fake verifier is injected here); events map to a
# BroadcastDelivery via the message tags SES echoes on every event.
class SesWebhookTest < ActionDispatch::IntegrationTest
  setup do
    @broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 1)
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    @delivery = @broadcast.deliveries.create!(subscriber: @subscriber, sent_at: Time.current)
  end

  teardown { Webhooks::SesController.message_verifier = nil }

  test "a signed delivery event stamps the delivery and bumps the counter" do
    post_event("Delivery")

    assert_response :ok
    assert @delivery.reload.delivered_at
    assert_equal 1, @broadcast.reload.delivered_count
  end

  test "duplicate opens count once" do
    post_event("Open")
    post_event("Open")

    assert_equal 1, @broadcast.reload.opened_count
  end

  test "a permanent bounce stamps bounced" do
    post_event("Bounce", extra: { "bounce" => { "bounceType" => "Permanent" } })

    assert @delivery.reload.bounced_at
    assert_equal 1, @broadcast.reload.bounced_count
  end

  test "a transient bounce is ignored — SES keeps retrying" do
    post_event("Bounce", extra: { "bounce" => { "bounceType" => "Transient" } })

    assert_nil @delivery.reload.bounced_at
    assert_equal 0, @broadcast.reload.bounced_count
  end

  test "a complaint records and drops the subscriber from the list" do
    post_event("Complaint")

    assert @delivery.reload.complained_at
    assert_equal 1, @broadcast.reload.complained_count
    assert @subscriber.reload.unsubscribed?
  end

  test "a bad signature is rejected and records nothing" do
    post_notification(ses_event("Delivery"), authentic: false)

    assert_response :unauthorized
    assert_equal 0, @broadcast.reload.delivered_count
  end

  test "an event for an unknown delivery is a no-op 200" do
    post_event("Open", subscriber_id: 999_999)

    assert_response :ok
    assert_equal 0, @broadcast.reload.opened_count
  end

  test "a subscription confirmation is auto-confirmed by fetching the url" do
    fetched = nil
    url = "https://sns.us-east-1.amazonaws.com/confirm?x=1"
    original = Net::HTTP.method(:get)
    Net::HTTP.define_singleton_method(:get) { |uri| fetched = uri.to_s; "ok" }

    begin
      post_body({ "Type" => "SubscriptionConfirmation", "SubscribeURL" => url }, authentic: true)
    ensure
      Net::HTTP.define_singleton_method(:get, original)
    end

    assert_response :ok
    assert_equal url, fetched
  end

  private
    def ses_event(event_type, broadcast_id: @broadcast.id, subscriber_id: @subscriber.id, extra: {})
      {
        "eventType" => event_type,
        "mail" => {
          "messageId" => "0000-abc",
          "tags" => {
            "ses:configuration-set" => [ "inkwell-marketing" ],
            "broadcast_id" => [ broadcast_id.to_s ],
            "subscriber_id" => [ subscriber_id.to_s ]
          }
        }
      }.merge(extra)
    end

    def post_event(event_type, subscriber_id: @subscriber.id, extra: {})
      post_notification(ses_event(event_type, subscriber_id: subscriber_id, extra: extra))
    end

    def post_notification(event, authentic: true)
      post_body({ "Type" => "Notification", "Message" => event.to_json }, authentic: authentic)
    end

    # SNS posts the raw JSON as text/plain; drive the controller through the same
    # path with the signature verifier injected to the desired verdict.
    def post_body(sns_message, authentic:)
      Webhooks::SesController.message_verifier = verifier(authentic)
      post "/webhooks/ses", params: sns_message.to_json,
        headers: { "CONTENT_TYPE" => "text/plain" }
    end

    def verifier(authentic)
      fake = Object.new
      fake.define_singleton_method(:authentic?) { |_body| authentic }
      fake
    end
end
