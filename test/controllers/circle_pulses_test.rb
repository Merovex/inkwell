require "test_helper"

class CirclePulsesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { @circle = circles(:writers) }

  def create_pulse(**attrs)
    Current.with_bucket(@circle) do
      Record.originate(Pulse.new({ question: "What did you work on?", creator: users(:alice),
        cadence: "weekly", days_of_week: (1 << 1), ask_at_minutes: 540 }.merge(attrs)))
    end.recordable
  end

  test "the owner sets up a check-in and every member is subscribed by default" do
    sign_in_as users(:alice) # owner

    assert_difference -> { @circle.pulses.count }, 1 do
      post circle_pulses_path(@circle), params: {
        pulse: { question: "Daily standup?", cadence: "daily", ask_at_minutes: 990,
                 active: "1", weekdays: %w[1 3 5] } }
    end

    pulse = @circle.pulse
    assert_equal "Daily standup?", pulse.question
    # Mon/Wed/Fri bits set.
    assert pulse.weekday_selected?(Date.new(2024, 1, 1)) # a Monday
    assert_redirected_to circle_pulse_path(@circle, pulse.record)
    # Owner + member both auto-subscribed.
    assert pulse.subscribed?(users(:alice))
    assert pulse.subscribed?(users(:bob))
  end

  test "the setup form renders with standard field classes and a text input for the question" do
    sign_in_as users(:alice)

    get new_circle_pulse_path(@circle)
    assert_response :success
    assert_select "input.field__control[name=?][type=text]", "pulse[question]"
    assert_select "textarea[name=?]", "pulse[question]", count: 0
    # Cadence is a dropdown; the schedule row groups cadence, day pills, and time.
    assert_select ".pulse-schedule .field__select select[name=?]", "pulse[cadence]"
    assert_select ".pulse-schedule .day-pills .day-pill__input[name=?]", "pulse[weekdays][]"
    assert_select ".pulse-schedule .field__select select.field__control[name=?]", "pulse[ask_at_minutes]"
  end

  test "monthly clamps to a single weekday even if several are submitted" do
    sign_in_as users(:alice)

    post circle_pulses_path(@circle), params: {
      pulse: { question: "Monthly?", cadence: "monthly", ask_at_minutes: 540,
               active: "1", weekdays: %w[1 3 5] } } # Mon, Wed, Fri

    pulse = @circle.pulse
    assert_equal 1, pulse.selected_day_names.size
    assert_equal %w[Monday], pulse.selected_day_names # the lowest-numbered day kept
  end

  test "a non-owner member cannot set up or edit a check-in" do
    create_pulse
    sign_in_as users(:bob) # member, not owner

    get new_circle_pulse_path(@circle)
    assert_response :not_found
  end

  test "a member can leave and rejoin a check-in" do
    pulse = create_pulse
    sign_in_as users(:bob)

    delete circle_pulse_subscription_path(@circle, pulse.record)
    assert_not pulse.subscribed?(users(:bob))

    post circle_pulse_subscription_path(@circle, pulse.record)
    assert pulse.subscribed?(users(:bob))
  end

  test "a member beats, and a second beat edits the first" do
    pulse = create_pulse
    pulse.update_column(:last_asked_on, Date.current)
    sign_in_as users(:bob)

    assert_difference -> { pulse.beats.count }, 1 do
      post circle_pulse_beats_path(@circle, pulse.record), params: { beat: { content: "<p>Shipped it</p>" } }
    end
    assert_equal "Circle", pulse.beats.first.record.bucket_type

    # A second submission edits, not duplicates.
    assert_no_difference -> { pulse.beats.count } do
      post circle_pulse_beats_path(@circle, pulse.record), params: { beat: { content: "<p>Actually two things</p>" } }
    end
    assert_match "two things", pulse.beats_on(Date.current).find_by(creator_id: users(:bob).id).content.to_plain_text
  end

  test "the check-in page shares everyone's answers" do
    pulse = create_pulse
    pulse.update_column(:last_asked_on, Date.current)
    Current.with_bucket(@circle) do
      Record.originate(Beat.new(content: "<p>Alice here</p>", asked_on: Date.current, creator: users(:alice)), parent: pulse.record)
    end
    sign_in_as users(:bob)

    get circle_pulse_path(@circle, pulse.record)
    assert_response :success
    assert_select "#beats .comment__body", text: /Alice here/
  end

  test "after answering, the composer yields to the answer's own Edit" do
    pulse = create_pulse
    pulse.update_column(:last_asked_on, Date.current)
    sign_in_as users(:bob)
    post circle_pulse_beats_path(@circle, pulse.record), params: { beat: { content: "<p>Shipped it</p>" } }

    get circle_pulse_path(@circle, pulse.record)
    assert_select "[aria-label='Your answer']", count: 0        # composer gone
    beat_record = pulse.beats_on(Date.current).find_by(creator_id: users(:bob).id).record
    assert_select "#beat_#{beat_record.id} a", text: "Edit"
  end

  test "the author edits an answer inline; the edit lands as a tracked version" do
    pulse = create_pulse
    pulse.update_column(:last_asked_on, Date.current)
    sign_in_as users(:bob)
    post circle_pulse_beats_path(@circle, pulse.record), params: { beat: { content: "<p>Shipped it</p>" } }
    beat_record = pulse.beats_on(Date.current).find_by(creator_id: users(:bob).id).record

    get edit_circle_pulse_beat_path(@circle, pulse.record, beat_record)
    assert_response :success
    assert_select "form [aria-label='Your answer']"

    patch circle_pulse_beat_path(@circle, pulse.record, beat_record),
      params: { beat: { content: "<p>Actually two things</p>" } }
    assert_redirected_to circle_pulse_path(@circle, pulse.record, anchor: "beat_#{beat_record.id}")
    beat = pulse.beats_on(Date.current).find_by(creator_id: users(:bob).id)
    assert_match "two things", beat.content.to_plain_text
    assert beat.event_updated?
  end

  test "another member cannot edit someone else's answer" do
    pulse = create_pulse
    pulse.update_column(:last_asked_on, Date.current)
    Current.with_bucket(@circle) do
      Record.originate(Beat.new(content: "<p>Alice here</p>", asked_on: Date.current, creator: users(:alice)), parent: pulse.record)
    end
    beat_record = pulse.beats_on(Date.current).find_by(creator_id: users(:alice).id).record
    sign_in_as users(:bob)

    get edit_circle_pulse_beat_path(@circle, pulse.record, beat_record)
    assert_response :not_found
    patch circle_pulse_beat_path(@circle, pulse.record, beat_record),
      params: { beat: { content: "<p>Hijacked</p>" } }
    assert_response :not_found
    assert_match "Alice here", pulse.beats_on(Date.current).find_by(creator_id: users(:alice).id).content.to_plain_text
  end

  test "the circle home previews the pulse with its latest answers, one big door" do
    pulse = create_pulse
    pulse.update_column(:last_asked_on, Date.current)
    Current.with_bucket(@circle) do
      Record.originate(Beat.new(content: "<p>Wrote through the block today</p>", asked_on: Date.current, creator: users(:alice)), parent: pulse.record)
    end
    sign_in_as users(:bob)

    get circle_path(@circle)
    assert_select "#pulse-heading", text: "Pulse check"
    assert_select "a.pulse-preview[href=?]", circle_pulse_path(@circle, pulse.record)
    assert_select ".pulse-preview__question", text: pulse.question
    assert_select ".pulse-preview__card", count: 1
    assert_select ".pulse-preview__byline", text: /#{users(:alice).display_name}.*ago/m
    assert_select ".pulse-preview__excerpt", text: /Wrote through the block/
  end
end
