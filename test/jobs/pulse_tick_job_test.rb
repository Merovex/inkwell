require "test_helper"

class PulseTickJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup { @circle = circles(:writers) }

  def create_pulse(**attrs)
    Current.with_bucket(@circle) do
      Record.originate(Pulse.new({ question: "Q?", creator: users(:alice),
        cadence: "daily", active: true, ask_at_minutes: 0 }.merge(attrs)))
    end.recordable
  end

  test "it asks a due pulse once, emailing every subscriber, and won't ask twice the same day" do
    monday = Date.new(2026, 8, 3) # a Monday
    pulse = create_pulse(days_of_week: (1 << monday.wday))
    PulseSubscription.create!(pulse_record: pulse.record, user: users(:alice))
    PulseSubscription.create!(pulse_record: pulse.record, user: users(:bob))

    travel_to monday.to_time.change(hour: 9) do
      assert_enqueued_emails 2 do
        PulseTickJob.perform_now
      end
    end
    assert_equal monday, pulse.reload.last_asked_on

    # Same day again → no re-ask.
    travel_to monday.to_time.change(hour: 17) do
      assert_no_enqueued_emails { PulseTickJob.perform_now }
    end
  end

  test "it skips a pulse whose day or time hasn't come, and paused pulses" do
    monday = Date.new(2026, 8, 3)
    # Due only on Tuesday — not today.
    create_pulse(days_of_week: (1 << (monday.wday + 1)))
    # Due today but paused.
    create_pulse(days_of_week: (1 << monday.wday), active: false)

    travel_to monday.to_time.change(hour: 12) do
      assert_no_enqueued_emails { PulseTickJob.perform_now }
    end
  end
end
