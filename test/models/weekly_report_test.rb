require "test_helper"

# One site's week — the numbers behind a per-site section of the digest.
class WeeklyReportTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:merovex)
    @week_of = Date.new(2026, 8, 3)
    @day = @week_of + 2.days
  end

  test "subscriber movement, trend, and delta" do
    joiner = @account.subscribers.create!(email_address: "n@example.com", status: :confirmed, source: "nav form")
    joiner.events.create!(action: "confirmed", created_at: @day)
    @account.subscriber_snapshots.create!(week_of: @week_of - 7, confirmed_count: 5)
    @account.subscriber_snapshots.create!(week_of: @week_of, confirmed_count: 7)

    report = WeeklyReport.new(@account, week_of: @week_of)

    assert_equal 7, report.confirmed_count
    assert_equal 2, report.confirmed_delta
    assert_equal 1, report.joined
    assert_equal({ "nav form" => 1 }, report.joined_by_source)
    assert_equal 0, report.unsubscribed
    assert_equal [ 5, 7 ], report.trend
    assert report.changed?
  end

  test "a send this week rolls up delivered, bounced, and the bounced address" do
    broadcast = records(:kickoff).create_broadcast!
    broadcast.update!(sent_at: @day, recipients_count: 14, delivered_count: 14, bounced_count: 1)
    bouncer = @account.subscribers.create!(email_address: "old-address@sbcglobal.net", status: :bounced)
    broadcast.deliveries.create!(subscriber: bouncer, bounced_at: @day)

    report = WeeklyReport.new(@account, week_of: @week_of)

    assert report.sent_any?
    assert_equal 14, report.delivered
    assert_equal 1, report.bounced
    assert_in_delta 0.0714, report.bounce_rate, 0.001
    assert_includes report.bounced_addresses, "old-address@sbcglobal.net"
    assert report.changed?
  end

  test "a quiet week reports no change" do
    # An empty historical week — no fixture content lands in it.
    assert_not WeeklyReport.new(@account, week_of: Date.new(2020, 1, 6)).changed?
  end
end
