require "test_helper"

class PostBroadcastJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @broadcast = records(:kickoff).create_broadcast!
    Subscriber.create!(email_address: "a@example.com", status: :confirmed)
    Subscriber.create!(email_address: "b@example.com", status: :confirmed)
    Subscriber.create!(email_address: "pending@example.com", status: :pending)
  end

  test "mails only confirmed subscribers and records the outcome" do
    assert_emails 2 do
      PostBroadcastJob.perform_now(@broadcast)
    end

    assert @broadcast.reload.sent?
    assert_equal 2, @broadcast.recipients_count
    assert_equal 2, @broadcast.deliveries.count
    assert @broadcast.deliveries.all?(&:sent_at)
  end

  test "re-running does not re-mail anyone (idempotent, resumable)" do
    PostBroadcastJob.perform_now(@broadcast)

    assert_no_emails do
      PostBroadcastJob.perform_now(@broadcast)
    end
    assert_equal 2, @broadcast.reload.deliveries.count
  end
end
