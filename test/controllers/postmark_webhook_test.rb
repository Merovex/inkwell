require "test_helper"

# Postmark event webhooks → broadcast/drip metrics. Authenticity is HTTP Basic
# Auth (a test credential is injected via the controller seam); events map to a
# delivery via the ids Postmark echoes in Metadata.
class PostmarkWebhookTest < ActionDispatch::IntegrationTest
  CREDS = %w[ hook s3cret ].freeze

  setup do
    Webhooks::PostmarkController.basic_auth_credentials = CREDS
    @broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 1)
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    @delivery = @broadcast.deliveries.create!(subscriber: @subscriber, sent_at: Time.current)
  end

  teardown { Webhooks::PostmarkController.basic_auth_credentials = nil }

  test "a delivery event stamps the delivery and bumps the counter" do
    post_event("Delivery")

    assert_response :ok
    assert @delivery.reload.delivered_at
    assert_equal 1, @broadcast.reload.delivered_count
  end

  test "an open marks the subscriber engaged, and duplicate opens count once" do
    post_event("Open")
    post_event("Open")

    assert_equal 1, @broadcast.reload.opened_count
    assert @subscriber.reload.last_engaged_at
  end

  test "a click stamps the delivery" do
    post_event("Click")

    assert @delivery.reload.clicked_at
    assert_equal 1, @broadcast.reload.clicked_count
  end

  test "a hard bounce stamps bounced" do
    post_event("Bounce", extra: { "Type" => "HardBounce" })

    assert @delivery.reload.bounced_at
    assert_equal 1, @broadcast.reload.bounced_count
  end

  test "a soft bounce is ignored — Postmark keeps retrying" do
    post_event("Bounce", extra: { "Type" => "SoftBounce" })

    assert_nil @delivery.reload.bounced_at
    assert_equal 0, @broadcast.reload.bounced_count
  end

  test "a spam complaint records and drops the subscriber from the list" do
    post_event("SpamComplaint")

    assert @delivery.reload.complained_at
    assert_equal 1, @broadcast.reload.complained_count
    assert @subscriber.reload.unsubscribed?
  end

  test "missing basic auth is rejected and records nothing" do
    post "/webhooks/postmark", params: event("Delivery").to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :unauthorized
    assert_equal 0, @broadcast.reload.delivered_count
  end

  test "wrong basic auth is rejected" do
    post_event("Delivery", auth: %w[ hook wrong ])

    assert_response :unauthorized
    assert_equal 0, @broadcast.reload.delivered_count
  end

  test "an event for an unknown delivery is a no-op 200" do
    post_event("Open", subscriber_id: 999_999)

    assert_response :ok
    assert_equal 0, @broadcast.reload.opened_count
  end

  test "processes the POST even with forgery protection on (no CSRF token)" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      post_event("Delivery")
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    assert_response :ok
    assert @delivery.reload.delivered_at
  end

  test "a drip open routes to the drop delivery via drop_record_id" do
    drop_delivery = build_drop_delivery
    post "/webhooks/postmark",
      params: { "RecordType" => "Open",
        "Metadata" => { "drop_record_id" => drop_delivery.drop_record_id.to_s,
                        "subscriber_id" => drop_delivery.subscriber_id.to_s } }.to_json,
      headers: postmark_headers(CREDS)

    assert_response :ok
    assert drop_delivery.reload.opened_at
  end

  private
    def event(record_type, broadcast_id: @broadcast.id, subscriber_id: @subscriber.id, extra: {})
      {
        "RecordType" => record_type,
        "MessageStream" => "broadcast",
        "Recipient" => @subscriber.email_address,
        "Metadata" => { "broadcast_id" => broadcast_id.to_s, "subscriber_id" => subscriber_id.to_s }
      }.merge(extra)
    end

    def post_event(record_type, subscriber_id: @subscriber.id, extra: {}, auth: CREDS)
      post "/webhooks/postmark",
        params: event(record_type, subscriber_id: subscriber_id, extra: extra).to_json,
        headers: postmark_headers(auth)
    end

    def postmark_headers(auth)
      { "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(*auth) }
    end

    def build_drop_delivery
      creator = users(:admin)
      drip = Drip.new(title: "Welcome", active: true, creator:)
      Record.originate(drip)
      drop = Drop.new(subject: "Hi", delay_days: 0, creator:)
      drop.body = "x"
      Record.originate(drop, parent: drip.record)
      stream = drip.enroll(@subscriber)
      DropDelivery.create!(stream:, drop_record: drop.record, subscriber: @subscriber,
        status: :sent, sent_at: Time.current)
    end
end
