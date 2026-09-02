require "test_helper"

# Goals: personal practice targets bucketed to the USER (not a site or
# circle), reported against with Tallies. Both are mutable recordables —
# edits amend in place, never versions.
class GoalsTest < ActionDispatch::IntegrationTest
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

  test "an author sets a goal on their own shelf" do
    sign_in_as users(:bob)

    assert_difference -> { Goal.count }, 1 do
      post goals_path, params: { goal: { title: "Draft the novel", unit: "words", target: 50000 } }
    end
    record = Goal.last.record
    assert_equal [ "User", users(:bob).id ], [ record.bucket_type, record.bucket_id ]
    assert_redirected_to goal_path(record)
  end

  test "goals are private to their author — even from root" do
    goal = create_goal
    sign_in_as users(:alice) # root

    get goal_path(goal.record)
    assert_response :not_found
    get goals_path
    assert_select ".goal-summary__title", text: goal.title, count: 0
  end

  test "the index shows each goal as its one chosen tile with a context menu" do
    goal = create_goal(target: 1000)
    log_tally(goal, amount: 250)
    sign_in_as users(:bob)

    get goals_path
    assert_select ".goal-summary__title a[href=?]", goal_path(goal.record), text: "Draft the novel"
    # One tile only — the goal's display choice (auto → completion bar here).
    assert_select ".goal-stat", count: 1
    assert_select ".goal-stat__value", text: "25%"
    assert_select ".goal-stat__bar-fill[style=?]", "inline-size: 25%"
    assert_select ".goal-stat__meta", text: "250 of 1,000 words"
    # Quick today-log on the card, left of the ⋯ menu (which keeps goal actions).
    assert_select ".goal-summary__actions a[href=?][aria-label=?]",
      today_goal_tallies_path(goal.record), "Edit today's tally"
    assert_select ".goal-summary__actions a[href=?]", edit_goal_path(goal.record), text: "Edit goal"
    assert_select ".goal-summary__actions form[action=?]", goal_archive_path(goal.record)
    # The design-studies gallery is retired from the page.
    assert_select ".goal-studies", count: 0
  end

  test "archiving retires a goal to the archived page, restorable" do
    goal = create_goal
    sign_in_as users(:bob)

    post goal_archive_path(goal.record)
    get goals_path
    assert_select ".goal-summary__title", text: goal.title, count: 0
    assert_select "a[href=?]", archived_goals_path, text: "View 1 archived goal"

    get archived_goals_path
    assert_select ".list__title", text: goal.title
    delete goal_archive_path(goal.record)
    get goals_path
    assert_select ".goal-summary__title", text: goal.title
  end

  test "the new-goal form arrives as a self-opening modal in the turbo frame" do
    sign_in_as users(:bob)

    get new_goal_path
    assert_response :success
    assert_select "turbo-frame#modal [data-dialog-open-value=true] dialog.modal"
    assert_select "dialog form select[name=?]", "goal[unit]"
  end

  test "a tally logs against the goal, defaulting to today" do
    goal = create_goal
    sign_in_as users(:bob)

    assert_difference -> { goal.tallies.count }, 1 do
      post goal_tallies_path(goal.record), params: { tally: { amount: 1200, note: "Rewrote chapter 3", logged_on: "" } }
    end
    tally = goal.tallies.first
    assert_equal Date.current, tally.logged_on
    assert_equal "Rewrote chapter 3", tally.note
  end

  test "a rate goal requires a target, and the modal offers the per dropdown" do
    sign_in_as users(:bob)

    get new_goal_path
    assert_select "dialog form select[name=?]", "goal[per]" do
      assert_select "option[value=day]", text: "per day"
    end

    assert_no_difference -> { Goal.count } do
      post goals_path, params: { goal: { title: "Daily words", unit: "words", per: "day" } }
    end
    assert_redirected_to goals_path # back with the validation alert
  end

  test "a rate goal observes every tally in its unit across the owner's goals" do
    novel = create_goal(title: "Novel", target: 50_000)
    pace  = create_goal(title: "Daily pace", target: 2_000, per: "day")
    hours = create_goal(title: "Editing", unit: "hours")
    log_tally(novel, amount: 1_400)
    log_tally(pace, amount: 600)
    log_tally(hours, amount: 3) # different unit — invisible to the words rate

    assert_equal 2_000, pace.period_total          # novel words + its own
    assert_equal 1_400, novel.total                # attribution untouched
    sign_in_as users(:bob)

    get goals_path
    assert_select ".goal-stat__ring-text", text: "100%"
    assert_select ".goal-stat__meta", text: /2,000 of 2,000 words/
  end

  test "calendar and heatmap displays render real history, heatmap full-width" do
    calendar = create_goal(title: "Calendar goal", displays: %w[calendar])
    heatmap  = create_goal(title: "Heatmap goal", displays: %w[heatmap])
    log_tally(calendar, amount: 1_200)
    sign_in_as users(:bob)

    get goals_path
    assert_select ".goal-summary--wide .goal-history__heat"   # heatmap spans the row
    assert_select ".goal-history__day--logged", minimum: 1    # today filled on the calendar
    assert_select ".goal-stat__meta", text: /logged on 1 of/

    # A prior year with tallies earns its own strip, GH-style.
    log_tally(heatmap, amount: 900, logged_on: Date.new(Date.current.year - 1, 6, 15))
    get goal_path(heatmap.record)
    assert_select ".goal-stat--wide .goal-history__heat", minimum: 2  # 365d + the prior year
    assert_select ".goal-stat__label", text: (Date.current.year - 1).to_s
  end

  test "a deadline project renders the race line: behind/ahead, needed-per-day, dashed target" do
    # 10-day window, 10,000 target, 3,000 logged by day 5 → 2,000 behind,
    # 1,167/day (ceil of 7,000 over 6 remaining days) to land it.
    goal = create_goal(title: "NaNo", target: 10_000,
      starts_on: Date.current - 4, ends_on: Date.current + 5)
    log_tally(goal, amount: 3_000, logged_on: Date.current - 2)
    sign_in_as users(:bob)

    # No picked displays: the deadline project auto-resolves to the pace card.
    get goals_path
    assert_select ".goal-stat__label", text: "Pace"
    assert_select ".goal-stat__value", text: /2,000\s*behind pace/
    assert_select ".goal-stat__meta", text: /needs 1,167\/day to finish by/
    assert_select ".goal-stat__chart-target"          # the dashed trajectory
    assert_select ".goal-stat__chart--line polyline"  # the actual line

    # The goal page's header carries the finish line.
    get goal_path(goal.record)
    assert_select ".perma-header__content time", text: (Date.current + 5).strftime("%b %-d")

    # The form offers the window fields.
    get new_goal_path
    assert_select "dialog input[type=date][name=?]", "goal[ends_on]"
    assert_select "dialog input[type=date][name=?]", "goal[starts_on]"
  end

  test "a deadline on a rate goal is rejected" do
    sign_in_as users(:bob)

    assert_no_difference -> { Goal.count } do
      post goals_path, params: { goal: { title: "Sprint", unit: "words",
        target: 500, per: "day", ends_on: Date.tomorrow } }
    end
    # The modal form's server-side misses land back on the index with the reason.
    assert_redirected_to goals_path
    assert_match(/in-total/, flash[:alert])
  end

  test "the author picks a set of progress views, stacked on the card" do
    ring_project = create_goal(title: "Ringed", target: 1000, displays: %w[ring heatmap])
    thirty = create_goal(title: "Thirty", displays: %w[rolling last30])
    log_tally(ring_project, amount: 250)
    sign_in_as users(:bob)

    get goals_path
    # Two cards for one goal — the heatmap leads (full row), the ring flexes
    # below with the other small cards; both foot-titled with the goal.
    assert_select ".goal-summary__title", text: "Ringed", count: 2
    assert_select ".goal-summary .goal-stat__ring-text", text: "25%"
    assert_select ".goal-summary--wide .goal-history__cell[data-level=3]", minimum: 1
    # The logbook's two trend picks are two more cards.
    assert_select ".goal-stat__label", text: "90-day Rolling"
    assert_select ".goal-stat__label", text: "Last 30 days"

    # The goal page reflects the same saved set (250 of 1,000 → 25%).
    get goal_path(ring_project.record)
    assert_select ".goal-stats--page .goal-stat__ring-text", text: "25%"

    # The modal offers the six views as checkbox-backed sample cards —
    # a set, no Auto card, no separate heat toggle.
    get new_goal_path
    assert_select "dialog .display-card input[type=checkbox][name=?]", "goal[displays][]", count: 6
    assert_select "dialog .display-card input[type=checkbox][value=rolling]"
    assert_select "dialog .display-card input[type=checkbox][value=heatmap]"
    assert_select "dialog input[name=?]", "goal[heat_map]", count: 0
  end

  test "the today modal starts a record, and the save lands back on the index" do
    goal = create_goal
    sign_in_as users(:bob)

    get today_goal_tallies_path(goal.record)
    assert_response :success
    assert_select "turbo-frame#modal dialog form[action=?]", goal_tallies_path(goal.record)
    assert_select "dialog input[name=?][value=?]", "tally[logged_on]", Time.zone.today.to_s

    post goal_tallies_path(goal.record), params: { back: "goals", tally: { amount: 400, logged_on: Time.zone.today } }
    assert_redirected_to goals_path
  end

  test "the today modal edits today's record when one exists" do
    goal = create_goal
    tally = log_tally(goal, amount: 300)
    sign_in_as users(:bob)

    get today_goal_tallies_path(goal.record)
    assert_select "turbo-frame#modal dialog form[action=?]", goal_tally_path(goal.record, tally.record_id)

    patch goal_tally_path(goal.record, tally.record_id),
      params: { back: "goals", tally: { amount: 500, logged_on: Time.zone.today } }
    assert_redirected_to goals_path
    assert_equal 500, tally.reload.amount
  end

  test "a note longer than an old tweet is rejected" do
    goal = create_goal
    sign_in_as users(:bob)

    assert_no_difference -> { goal.tallies.count } do
      post goal_tallies_path(goal.record), params: { tally: { amount: 100, note: "x" * 141 } }
    end
  end

  test "edits amend in place — no version rows" do
    goal = create_goal
    tally = log_tally(goal)
    sign_in_as users(:bob)

    patch goal_path(goal.record), params: { goal: { title: "Finish the novel", unit: "words" } }
    patch goal_tally_path(goal.record, tally.record_id), params: { tally: { amount: 750, logged_on: Date.current } }

    assert_equal 1, Goal.where(record_id: goal.record_id).count
    assert_equal 1, Tally.where(record_id: tally.record_id).count
    assert_equal "Finish the novel", goal.reload.title
    assert_equal 750, tally.reload.amount
  end

  test "a removed tally leaves the total" do
    goal = create_goal
    tally = log_tally(goal, amount: 300)
    log_tally(goal, amount: 200)
    sign_in_as users(:bob)

    delete goal_tally_path(goal.record, tally.record_id)
    assert_equal 200, goal.total
  end

  test "the goal page carries the logbook form and the tallies" do
    goal = create_goal
    log_tally(goal, amount: 1200, note: "Rewrote chapter 3")
    sign_in_as users(:bob)

    get goal_path(goal.record)
    assert_response :success
    assert_select "form.logbook [aria-label='Amount']"
    # Rows mirror the form's columns: date · amount · note, with a ⋯ menu.
    assert_select "#tallies .tally-row__amount", text: "1,200 words"
    assert_select "#tallies .tally-row__note", text: "Rewrote chapter 3"
    assert_select "#tallies .menu__item", text: "Edit"
  end
end
