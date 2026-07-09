require "test_helper"

class BroadcastTest < ActiveSupport::TestCase
  test "a record can be broadcast only once" do
    records(:kickoff).create_broadcast!

    assert_raises(ActiveRecord::RecordInvalid) { records(:kickoff).create_broadcast! }
  end

  test "post returns the record's current version" do
    broadcast = records(:kickoff).create_broadcast!

    assert_equal posts(:kickoff), broadcast.post
  end

  test "sent? reflects the sent_at stamp" do
    broadcast = records(:kickoff).create_broadcast!
    assert_not broadcast.sent?

    broadcast.update!(sent_at: Time.current)
    assert broadcast.sent?
  end

  test "rates use the newsletter denominators, and are nil when empty" do
    broadcast = records(:kickoff).create_broadcast!(
      recipients_count: 10, delivered_count: 8, opened_count: 4, clicked_count: 2)

    assert_in_delta 0.8,  broadcast.delivery_rate, 0.001  # 8 / 10 recipients
    assert_in_delta 0.5,  broadcast.open_rate,     0.001  # 4 / 8 delivered
    assert_in_delta 0.25, broadcast.click_rate,    0.001  # 2 / 8 delivered

    empty = Broadcast.new
    assert_nil empty.delivery_rate
    assert_nil empty.open_rate
  end
end
