require "test_helper"

class BroadcastDeliveryTest < ActiveSupport::TestCase
  setup do
    @broadcast = records(:kickoff).create_broadcast!(recipients_count: 1)
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    @delivery = @broadcast.deliveries.create!(subscriber: subscriber, sent_at: Time.current)
  end

  test "record_event stamps once and bumps the broadcast counter" do
    assert @delivery.record_event!("opened")
    assert @delivery.reload.opened_at
    assert_equal 1, @broadcast.reload.opened_count

    assert_not @delivery.record_event!("opened"), "a repeat open is a no-op"
    assert_equal 1, @broadcast.reload.opened_count, "unique opens only"
  end

  test "status reports the furthest milestone, worst news first" do
    assert_equal :sent, @delivery.status, "handed to the ESP, nothing heard back"
    assert_not @delivery.trouble?

    @delivery.record_event!("delivered")
    assert_equal :delivered, @delivery.status

    @delivery.record_event!("bounced")
    assert_equal :bounced, @delivery.status, "trouble outranks a prior delivery"
    assert @delivery.trouble?

    @delivery.record_event!("complained")
    assert_equal :complained, @delivery.status
    assert @delivery.trouble?
  end

  test "status is pending until the fan-out stamps sent_at" do
    assert_equal :pending, @broadcast.deliveries.build.status
  end

  test "a delivery with no events never reads as delivered" do
    assert_not_equal :delivered, @delivery.status,
      "the dashboard column must not treat 'no bad news' as confirmed delivery"
  end

  test "unknown events are ignored" do
    assert_not @delivery.record_event!("nonsense")
    assert_equal 0, @broadcast.reload.opened_count
  end

  test "failed maps to bounced" do
    @delivery.record_event!("failed")
    assert @delivery.reload.bounced_at
    assert_equal 1, @broadcast.reload.bounced_count
  end
end
