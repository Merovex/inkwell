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
