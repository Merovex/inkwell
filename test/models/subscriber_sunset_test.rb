require "test_helper"

# Engagement-based sunset decisions (ADR 0014): cooling → nudge → grace → drop,
# with any open/click resetting the clock.
class SubscriberSunsetTest < ActiveSupport::TestCase
  test "no action while engagement is recent" do
    s = confirmed_subscriber(last_engaged_at: 10.days.ago)
    deliveries_at s, 5.days.ago, 20.days.ago
    assert_nil s.sunset_action
  end

  test "re-engage at the later of 90 days and 6 emails" do
    s = confirmed_subscriber
    deliveries_at s, *[ 100, 90, 80, 70, 60, 20 ].map(&:days).map(&:ago)
    assert_equal :re_engage, s.sunset_action
  end

  test "re-engage by the 275-day cap even with few emails" do
    s = confirmed_subscriber
    deliveries_at s, 300.days.ago, 280.days.ago
    assert_equal :re_engage, s.sunset_action
  end

  test "cold in days but too few emails and under the cap: no nudge yet" do
    s = confirmed_subscriber
    deliveries_at s, 120.days.ago, 100.days.ago
    assert_nil s.sunset_action
  end

  test "after the nudge, drop once the grace passes (90 days + 3 emails)" do
    s = confirmed_subscriber(re_engagement_sent_at: 100.days.ago)
    deliveries_at s, 200.days.ago, 95.days.ago, 60.days.ago, 30.days.ago
    assert_equal :drop, s.sunset_action
  end

  test "after the nudge, hold during the grace window" do
    s = confirmed_subscriber(re_engagement_sent_at: 20.days.ago)
    deliveries_at s, 200.days.ago, 10.days.ago
    assert_nil s.sunset_action
  end

  test "engagement resets the clock and clears a pending nudge" do
    s = confirmed_subscriber(re_engagement_sent_at: 100.days.ago)
    s.mark_engaged!

    assert_nil s.re_engagement_sent_at
    assert s.last_engaged_at
    deliveries_at s, 200.days.ago
    assert_nil s.sunset_action, "recent engagement → safe"
  end

  test "unconfirmed and never-emailed subscribers are left alone" do
    assert_nil Subscriber.create!(email_address: "p@example.com").sunset_action, "pending"
    assert_nil confirmed_subscriber.sunset_action, "confirmed but never emailed"
  end

  private
    def confirmed_subscriber(**attrs)
      Subscriber.create!(email_address: "cold-#{SecureRandom.hex(4)}@example.com",
        status: :confirmed, confirmed_at: 1.year.ago, **attrs)
    end

    # Give the subscriber one broadcast delivery per given sent time.
    def deliveries_at(subscriber, *times)
      times.each do |time|
        record = Record.create!(recordable_type: "Post", creator: users(:alice))
        Broadcast.create!(record: record).deliveries.create!(subscriber: subscriber, sent_at: time)
      end
    end
end
