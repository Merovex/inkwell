require "test_helper"

# The daily prune of dead opt-ins: pending rows older than 30 days go, everything
# else stays. Confirmed subscribers are untouched at any age.
class PendingSubscriberPurgeJobTest < ActiveSupport::TestCase
  test "deletes a subscriber still pending past 30 days, cascading its events" do
    stale = pending_since(31.days.ago)
    event_id = stale.events.first.id

    assert_difference -> { Subscriber.count }, -1 do
      PendingSubscriberPurgeJob.perform_now
    end
    assert_not Subscriber.exists?(stale.id)
    assert_not SubscriptionEvent.exists?(event_id)
  end

  test "keeps a subscriber pending within the 30-day window" do
    fresh = pending_since(29.days.ago)

    assert_no_difference -> { Subscriber.count } do
      PendingSubscriberPurgeJob.perform_now
    end
    assert Subscriber.exists?(fresh.id)
  end

  test "leaves the identity-free signup-source residue behind" do
    stale = pending_since(31.days.ago, ip: "203.0.113.7")
    fingerprint = stale.events.first.source_fingerprint

    PendingSubscriberPurgeJob.perform_now

    assert_not Subscriber.exists?(stale.id)
    residue = SignupSource.find_by(source_fingerprint: fingerprint)
    assert_equal "subscribed", residue.action
    assert_equal stale.account, residue.account
  end

  test "never touches a confirmed subscriber, however old" do
    confirmed = pending_since(1.year.ago)
    confirmed.confirm!

    assert_no_difference -> { Subscriber.count } do
      PendingSubscriberPurgeJob.perform_now
    end
    assert Subscriber.exists?(confirmed.id)
  end

  private
    def pending_since(time, ip: nil)
      subscriber = Subscriber.opt_in(email_address: "pending-#{SecureRandom.hex(4)}@example.com", ip:)
      subscriber.update_column(:created_at, time)
      subscriber
    end
end
