require "test_helper"

class PulseTest < ActiveSupport::TestCase
  setup do
    @circle = circles(:writers)
  end

  def create_pulse(**attrs)
    Current.with_bucket(@circle) do
      Record.originate(Pulse.new({ question: "What did you work on?", creator: users(:alice) }.merge(attrs)))
    end
  end

  test "a pulse is a circle-owned recordable" do
    record = create_pulse

    assert_equal "Circle", record.bucket_type
    assert_equal @circle.id, record.bucket_id
    assert_includes @circle.pulses.map(&:record_id), record.id
    assert_equal record.recordable, @circle.pulse
  end

  test "only circle members can subscribe; a member can, a stranger cannot" do
    pulse = create_pulse.recordable

    ok = PulseSubscription.new(pulse_record: pulse.record, user: users(:bob)) # member
    assert ok.valid?

    stranger = User.create!(email_address: "nope@example.com", role: :member)
    bad = PulseSubscription.new(pulse_record: pulse.record, user: stranger)
    assert_not bad.valid?
    assert_match(/member of the circle/, bad.errors.full_messages.to_sentence)
  end

  test "beats thread to the pulse and group by occurrence" do
    pulse = create_pulse.recordable
    today = Date.current

    Current.with_bucket(@circle) do
      Record.originate(Beat.new(content: "<p>Shipped it</p>", asked_on: today, creator: users(:bob)),
        parent: pulse.record)
      Record.originate(Beat.new(content: "<p>Wrote a chapter</p>", asked_on: today, creator: users(:alice)),
        parent: pulse.record)
    end

    assert_equal 2, pulse.beats.count
    assert_equal 2, pulse.beats_on(today).count
    assert_equal 0, pulse.beats_on(today - 1).count
    assert_equal "Circle", pulse.beats.first.record.bucket_type
  end

  test "monthly is due on the first selected weekday of the month, not the 1st" do
    # First Monday of Aug 2026 is the 3rd; the 10th is the second Monday.
    pulse = create_pulse(cadence: "monthly", days_of_week: (1 << 1)).recordable # Monday

    assert pulse.due_on?(Date.new(2026, 8, 3)),  "first Monday"
    assert_not pulse.due_on?(Date.new(2026, 8, 10)), "second Monday"
    assert_not pulse.due_on?(Date.new(2026, 8, 1)),  "the 1st (a Saturday)"
    assert_equal "the first Monday of each month", pulse.schedule_summary
  end

  test "ask_at renders minutes-past-midnight as a plain time label" do
    assert_equal "9:00 AM", create_pulse(ask_at_minutes: 540).recordable.ask_at
    assert_equal "4:30 PM", create_pulse(ask_at_minutes: 990).recordable.ask_at
    assert_equal "12:00 AM", create_pulse(ask_at_minutes: 0).recordable.ask_at
  end
end
