require "test_helper"

class DripTest < ActiveSupport::TestCase
  setup do
    @creator = users(:admin)
    @drip = build_drip(active: true)
  end

  test "enroll starts a stream anchored at the subscriber's confirmed_at" do
    sub = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: 3.days.ago)

    stream = @drip.enroll(sub)

    assert_equal sub, stream.subscriber
    assert_equal @drip.record_id, stream.drip_record_id
    assert_in_delta 3.days.ago.to_f, stream.enrolled_at.to_f, 5
  end

  test "enroll is idempotent per subscriber" do
    sub = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)

    first = @drip.enroll(sub)
    again = @drip.enroll(sub)

    assert_equal first.id, again.id
    assert_equal 1, @drip.streams.count
  end

  test "Drip.enroll only enrolls into active drips" do
    build_drip(active: false)  # a second, inactive campaign
    sub = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)

    Drip.enroll(sub)

    assert_equal [ @drip.record_id ], Stream.where(subscriber: sub).pluck(:drip_record_id)
  end

  test "drops returns current child drops ordered by position" do
    add_drop(subject: "Two", delay_days: 2, position: 2)
    add_drop(subject: "One", delay_days: 0, position: 1)

    assert_equal %w[ One Two ], @drip.drops.map(&:subject)
  end

  private
    def build_drip(active:)
      version = Drip.new(title: "Welcome", active:, creator: @creator)
      Record.originate(version)
      version
    end

    def add_drop(subject:, delay_days:, position:)
      version = Drop.new(subject:, delay_days:, creator: @creator)
      version.body = "Hello"
      Record.originate(version, parent: @drip.record)
      version.record.update!(position:)
      version
    end
end
