require "test_helper"

class PostBroadcastJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @broadcast = records(:kickoff).create_broadcast!
    Subscriber.create!(email_address: "a@example.com", status: :confirmed)
    Subscriber.create!(email_address: "b@example.com", status: :confirmed)
    Subscriber.create!(email_address: "pending@example.com", status: :pending)
    Subscriber.create!(email_address: "report@aboutmy.email", status: :confirmed)  # seed: confirmed but never broadcast to
  end

  test "mails only confirmed non-seed subscribers and records the outcome" do
    assert_emails 2 do
      PostBroadcastJob.perform_now(@broadcast)
    end

    assert @broadcast.reload.sent?
    assert_equal 2, @broadcast.recipients_count
    assert_equal 2, @broadcast.deliveries.count
    assert @broadcast.deliveries.all?(&:sent_at)
  end

  test "skips anyone the platform has suppressed for this site, without a delivery row" do
    suppressed = Subscriber.find_by!(email_address: "b@example.com")
    Suppression.impose!(person: suppressed.person, reason: :hard_bounce)

    assert_emails 1 do
      PostBroadcastJob.perform_now(@broadcast)
    end
    assert_equal 1, @broadcast.reload.recipients_count
    assert_nil @broadcast.deliveries.find_by(subscriber: suppressed), "no row — nothing was attempted"
    assert suppressed.reload.confirmed?, "the suppression is the platform's; this site's roster row is untouched"
  end

  test "re-running does not re-mail anyone (idempotent, resumable)" do
    PostBroadcastJob.perform_now(@broadcast)

    assert_no_emails do
      PostBroadcastJob.perform_now(@broadcast)
    end
    assert_equal 2, @broadcast.reload.deliveries.count
  end
end
