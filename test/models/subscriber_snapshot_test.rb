require "test_helper"

# The weekly reading behind the digest's trend + "up N on last week" baseline.
class SubscriberSnapshotTest < ActiveSupport::TestCase
  test "capture records the sendable count and the week's movement, idempotently" do
    account = accounts(:merovex)
    week_of = Date.new(2026, 8, 3)
    joiner = account.subscribers.create!(email_address: "joiner@example.com", status: :confirmed)
    leaver = account.subscribers.create!(email_address: "leaver@example.com", status: :confirmed)
    joiner.events.create!(action: "confirmed", created_at: week_of + 1.day)
    leaver.events.create!(action: "unsubscribed", created_at: week_of + 2.days)

    assert_difference -> { SubscriberSnapshot.count }, 1 do
      SubscriberSnapshot.capture(account, week_of: week_of)
    end

    snapshot = SubscriberSnapshot.find_by!(account: account, week_of: week_of)
    assert_equal 2, snapshot.confirmed_count  # both still confirmed = sendable
    assert_equal 1, snapshot.joined_count
    assert_equal 1, snapshot.unsubscribed_count

    # A re-run refreshes the same row rather than doubling the week.
    assert_no_difference -> { SubscriberSnapshot.count } do
      SubscriberSnapshot.capture(account, week_of: week_of)
    end
  end
end
