require "test_helper"

# Stream#advance! — the send/skip decision at the heart of the drip runner.
class StreamAdvanceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @creator = users(:admin)
    @drip = new_drip
    @day0 = add_drop(subject: "Welcome", delay_days: 0, position: 1)
    @day3 = add_drop(subject: "Day three", delay_days: 3, position: 2)
    @sub = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    @stream = @drip.enroll(@sub)
  end

  test "sends the day-0 drop immediately and leaves the future drop pending" do
    assert_emails 1 do
      @stream.advance!
    end
    assert_equal "sent", @stream.deliveries.find_by(drop_record: @day0.record).status
    assert_nil @stream.deliveries.find_by(drop_record: @day3.record), "day-3 drop isn't due yet"
  end

  test "sends the later drop once its day arrives" do
    @stream.advance!
    assert_emails 1 do
      @stream.advance!(now: 3.days.from_now)
    end
    assert_equal "sent", @stream.deliveries.find_by(drop_record: @day3.record).status
  end

  test "advancing again sends nothing new (idempotent)" do
    @stream.advance!
    assert_no_emails { @stream.advance! }
  end

  test "records a skip instead of mailing when the subscriber has unsubscribed" do
    @sub.update!(status: :unsubscribed, unsubscribed_at: Time.current)

    assert_no_emails { @stream.advance! }

    delivery = @stream.deliveries.find_by(drop_record: @day0.record)
    assert_equal "skipped", delivery.status
    assert_equal "unsubscribed", delivery.skip_reason
  end

  test "an ended stream advances to nothing" do
    @stream.end!("unsubscribed")
    assert_no_emails { @stream.advance! }
    assert_empty @stream.deliveries
  end

  private
    def new_drip
      version = Drip.new(title: "Welcome", active: true, creator: @creator)
      Record.originate(version)
      version
    end

    def add_drop(subject:, delay_days:, position:)
      version = Drop.new(subject:, delay_days:, creator: @creator)
      version.body = "<p>#{subject}</p>"
      Record.originate(version, parent: @drip.record)
      version.record.update!(position:)
      version
    end
end
