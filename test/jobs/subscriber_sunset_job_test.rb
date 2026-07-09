require "test_helper"

class SubscriberSunsetJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup { Rails.configuration.x.newsletter.sunset_enabled = true }
  teardown { Rails.configuration.x.newsletter.sunset_enabled = false }

  test "does nothing while the sunset gate is off" do
    Rails.configuration.x.newsletter.sunset_enabled = false
    subscriber = needs_nudge

    assert_no_enqueued_emails { SubscriberSunsetJob.perform_now }
    assert_nil subscriber.reload.re_engagement_sent_at
  end

  test "nudges a cold subscriber once" do
    subscriber = needs_nudge

    assert_enqueued_emails(1) { SubscriberSunsetJob.perform_now }
    assert subscriber.reload.re_engagement_sent_at

    # Re-running doesn't nudge again (guarded by re_engagement_sent_at).
    assert_no_enqueued_emails { SubscriberSunsetJob.perform_now }
  end

  test "drops the unresponsive after grace, logged as a sunset" do
    subscriber = needs_drop

    SubscriberSunsetJob.perform_now
    assert subscriber.reload.unsubscribed?
    assert_equal "sunset", subscriber.events.last.source
  end

  private
    def needs_nudge
      s = Subscriber.create!(email_address: "nudge-#{SecureRandom.hex(4)}@example.com",
        status: :confirmed, confirmed_at: 1.year.ago)
      deliveries_at s, *[ 100, 90, 80, 70, 60, 20 ].map(&:days).map(&:ago)
      s
    end

    def needs_drop
      s = Subscriber.create!(email_address: "drop-#{SecureRandom.hex(4)}@example.com",
        status: :confirmed, confirmed_at: 1.year.ago, re_engagement_sent_at: 100.days.ago)
      deliveries_at s, 200.days.ago, 95.days.ago, 60.days.ago, 30.days.ago
      s
    end

    def deliveries_at(subscriber, *times)
      times.each do |time|
        record = Record.create!(recordable_type: "Post", creator: users(:alice))
        Broadcast.create!(record: record).deliveries.create!(subscriber: subscriber, sent_at: time)
      end
    end
end
