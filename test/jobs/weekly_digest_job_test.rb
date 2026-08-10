require "test_helper"

class WeeklyDigestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @account = accounts(:merovex)  # owned by alice
    @week_of = Date.new(2026, 8, 3)
    # Give alice's site something to report this week.
    records(:kickoff).create_broadcast!.update!(sent_at: @week_of + 1.day, recipients_count: 5, delivered_count: 5)
  end

  test "captures a snapshot per account and mails owners with activity" do
    assert_difference -> { SubscriberSnapshot.where(account: @account, week_of: @week_of).count }, 1 do
      assert_enqueued_email_with WeeklyDigestMailer, :weekly, args: [ users(:alice), @week_of, [ @account.id ] ] do
        WeeklyDigestJob.new.perform(week_of: @week_of)
      end
    end
    assert users(:alice).reload.last_digest_at.present?
  end

  test "skips users who turned the digest off" do
    users(:alice).update!(digest_cadence: "off")

    assert_no_enqueued_emails do
      WeeklyDigestJob.new.perform(week_of: @week_of)
    end
  end

  test "skips users not yet due (fortnightly, mailed last week)" do
    users(:alice).update!(digest_cadence: "fortnightly", last_digest_at: 3.days.ago)

    assert_no_enqueued_emails do
      WeeklyDigestJob.new.perform(week_of: @week_of)
    end
  end
end
