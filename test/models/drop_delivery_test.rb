require "test_helper"

class DropDeliveryTest < ActiveSupport::TestCase
  setup do
    creator = users(:admin)
    drip = Drip.new(title: "W", active: true, creator:)
    Record.originate(drip)
    @drop = Drop.new(subject: "Hi", delay_days: 0, creator:)
    @drop.body = "x"
    Record.originate(@drop, parent: drip.record)

    @sub = Subscriber.create!(email_address: "r@example.com", status: :confirmed, confirmed_at: Time.current)
    @stream = drip.enroll(@sub)
    @delivery = DropDelivery.create!(stream: @stream, drop_record: @drop.record, subscriber: @sub,
      status: :sent, sent_at: Time.current)
  end

  test "record_event stamps once and marks the subscriber engaged on open" do
    assert @delivery.record_event!("opened")
    assert @delivery.reload.opened_at
    assert @sub.reload.last_engaged_at

    assert_not @delivery.record_event!("opened"), "a repeat open is a no-op"
  end

  test "unknown events are ignored" do
    assert_not @delivery.record_event!("nonsense")
  end

  test "one delivery per (stream, drop)" do
    dup = DropDelivery.new(stream: @stream, drop_record: @drop.record, subscriber: @sub)
    assert_raises(ActiveRecord::RecordNotUnique) { dup.save!(validate: false) }
  end
end
