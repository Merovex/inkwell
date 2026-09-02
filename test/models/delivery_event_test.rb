require "test_helper"

# The canonical event pipeline: dedupe at the DB, raw payload kept for replay,
# side effects only on first sight, and the two traps — suppressed and rejected
# never touch the subscriber.
class DeliveryEventTest < ActiveSupport::TestCase
  setup do
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    @broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 1)
    @delivery = @broadcast.deliveries.create!(subscriber: @subscriber, sent_at: Time.current)
  end

  test "ingest! dedupes on provider + message id + event" do
    2.times { ingest(event: "hard_bounce", provider_message_id: "pm-1") }

    assert_equal 1, DeliveryEvent.count
    assert_equal [ "bounced" ], @subscriber.events.pluck(:action), "side effects apply once"
  end

  test "the raw payload is stored for replay" do
    event = ingest(event: "delivered", provider_message_id: "x",
      payload: { "mail" => { "messageId" => "x" } })

    assert_equal "x", event.reload.payload.dig("mail", "messageId")
  end

  test "soft bounces suppress only after three in a row" do
    2.times { |i| ingest(event: "soft_bounce", provider_message_id: "m-#{i}") }
    assert @subscriber.reload.confirmed?

    ingest(event: "soft_bounce", provider_message_id: "m-2")
    assert @subscriber.reload.bounced?
    assert @delivery.reload.bounced_at
  end

  test "a successful delivery resets the soft-bounce streak" do
    2.times { |i| ingest(event: "soft_bounce", provider_message_id: "m-#{i}") }
    ingest(event: "delivered", provider_message_id: "m-ok")

    ingest(event: "soft_bounce", provider_message_id: "m-3")
    assert @subscriber.reload.confirmed?
  end

  test "suppressed and rejected never touch the subscriber" do
    ingest(event: "suppressed", provider_message_id: "s-1", provider: "ses")
    ingest(event: "rejected", provider_message_id: "r-1")

    assert @subscriber.reload.confirmed?
    assert_nil @delivery.reload.bounced_at
  end

  test "an event with no matched delivery still records" do
    event = DeliveryEvent.ingest!(provider: "ses", event: "hard_bounce", payload: {},
      provider_message_id: "orphan", recipient: "ghost@example.com")

    assert event.persisted?
    assert_nil event.subscriber
    assert_equal "ghost@example.com", event.recipient
  end

  test "dispatch_stamp reads the carrying provider off the delivered message" do
    postmark = Mail.new
    postmark.header["X-PM-Message-Id"] = "pm-123"
    assert_equal({ provider: "postmark", provider_message_id: "pm-123" },
      DeliveryEvent.dispatch_stamp(postmark))

    ses = Mail.new
    ses.header[:ses_message_id] = "ses-123"
    assert_equal({ provider: "ses", provider_message_id: "ses-123" },
      DeliveryEvent.dispatch_stamp(ses))

    assert_equal({}, DeliveryEvent.dispatch_stamp(Mail.new), "test delivery method stamps nothing")
  end

  private
    def ingest(event:, provider_message_id:, provider: "postmark", payload: {})
      DeliveryEvent.ingest!(provider:, event:, payload:, provider_message_id:, delivery: @delivery)
    end
end
