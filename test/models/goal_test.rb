require "test_helper"

# The deadline window and its pace math (the NaNo race line): validations
# keep deadlines project-only; the pace methods measure against the straight
# line from start to target-at-deadline.
class GoalTest < ActiveSupport::TestCase
  def create_goal(user: users(:bob), **attrs)
    Current.with_bucket(user) do
      Record.originate(Goal.new({ title: "Draft the novel", unit: "words", creator: user }.merge(attrs)))
    end.recordable
  end

  def log_tally(goal, user: users(:bob), **attrs)
    Current.with_bucket(user) do
      Record.originate(
        Tally.new({ amount: 500, logged_on: Date.current, creator: user }.merge(attrs)),
        parent: goal.record)
    end.recordable
  end

  test "a deadline is project-only — rates and logbooks reject it" do
    rate = Goal.new(title: "Daily", unit: "words", target: 500, per: "day", ends_on: Date.tomorrow)
    assert_not rate.valid?
    assert rate.errors[:ends_on].any?

    logbook = Goal.new(title: "Log", unit: "words", ends_on: Date.tomorrow)
    assert_not logbook.valid?
    assert logbook.errors[:ends_on].any?

    project = Goal.new(title: "Novel", unit: "words", target: 50_000, ends_on: Date.tomorrow,
      creator: users(:bob))
    assert project.valid?
  end

  test "a start needs a deadline, and the deadline must come after it" do
    dangling = Goal.new(title: "Novel", unit: "words", target: 50_000, starts_on: Date.current)
    assert_not dangling.valid?
    assert dangling.errors[:starts_on].any?

    inverted = Goal.new(title: "Novel", unit: "words", target: 50_000,
      starts_on: Date.current, ends_on: Date.current)
    assert_not inverted.valid?
    assert inverted.errors[:ends_on].any?
  end

  test "pace_start prefers the explicit start, else first tally or creation — whichever is earlier" do
    explicit = create_goal(target: 30_000, starts_on: Date.current - 5, ends_on: Date.current + 10)
    assert_equal Date.current - 5, explicit.pace_start

    derived = create_goal(target: 30_000, ends_on: Date.current + 10)
    assert_equal Date.current, derived.pace_start, "no tallies → the creation day"

    log_tally(derived, logged_on: Date.current - 3)
    assert_equal Date.current - 3, derived.pace_start, "a backdated tally pulls the line back"
  end

  test "the pace line: target-for-today, delta, and needed-per-day" do
    # A 10-day window (D-4 .. D+5), 10,000 target → the line demands 1,000/day.
    goal = create_goal(target: 10_000, starts_on: Date.current - 4, ends_on: Date.current + 5)
    log_tally(goal, amount: 3_000, logged_on: Date.current - 2)

    assert_equal 10, goal.pace_days
    assert_equal 5_000, goal.pace_target_for(Date.current), "day 5 of 10"
    assert_equal(-2_000, goal.pace_delta, "3,000 logged against the 5,000 the line demands")
    assert_equal 1_167, goal.needed_per_day, "7,000 still to write over 6 remaining days, ceiled"
  end

  test "needed_per_day is zero once the target is hit or the deadline has passed" do
    done = create_goal(target: 1_000, starts_on: Date.current - 2, ends_on: Date.current + 2)
    log_tally(done, amount: 1_200)
    assert_equal 0, done.needed_per_day
    assert done.pace_delta.positive?

    over = create_goal(target: 1_000, starts_on: Date.current - 9, ends_on: Date.current - 1)
    assert_equal 0, over.needed_per_day
  end

  test "pace_target_for clamps outside the window — never negative, never past the target" do
    goal = create_goal(target: 10_000, starts_on: Date.current - 4, ends_on: Date.current + 5)

    assert_equal 0, goal.pace_target_for(Date.current - 30)
    assert_equal 10_000, goal.pace_target_for(Date.current + 30)
  end
end
