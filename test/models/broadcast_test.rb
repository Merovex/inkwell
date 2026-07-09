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
end
