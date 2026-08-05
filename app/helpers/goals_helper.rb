# The goal status tiles and their mini charts (inline SVG — no chart library).
# Drawing only: the data lives on Goal (#daily_series, #completion_percent).
module GoalsHelper
  # Weeks run Monday-first, matching Date#beginning_of_week.
  WEEKDAY_LABELS = %w[ Mon Tue Wed Thu Fri Sat Sun ].freeze

  def goal_week_series(goal, reference = Time.zone.today)
    goal.daily_series(reference.beginning_of_week..reference.end_of_week)
  end

  def goal_rolling_series(goal, days: 90)
    rolling_average(goal.daily_series((Time.zone.today - (days - 1))..Time.zone.today))
  end

  # The GitHub-style contribution strip, over any date range (default: the
  # trailing 365 days). Three intensity stops; invisible pad cells align the
  # first column to a week boundary, GH-style.
  def goal_heat_cells(goal, range: (Time.zone.today - 364)..Time.zone.today)
    series = goal.daily_series(range)
    max = series.max
    # GH-parity: heat weeks run Sunday-first (so Mon/Wed/Fri land on rows 2/4/6).
    pad = (range.first - range.first.beginning_of_week(:sunday)).to_i
    cells = Array.new(pad) { tag.span class: "goal-history__cell goal-history__cell--pad", "aria-hidden": true }
    cells += range.to_a.zip(series).map do |date, amount|
      level = amount.zero? ? 0 : (amount / max.to_f * 3).ceil
      tag.span class: "goal-history__cell", data: { level: level },
               title: "#{date.iso8601} — #{number_with_delimiter(amount)}"
    end
    safe_join(cells)
  end

  # Month labels for the heat map's top edge: [week_index, "Aug"] for each
  # week column containing a month's 1st — where GH puts them.
  def goal_heat_months(range)
    start = range.first.beginning_of_week(:sunday)
    weeks = ((range.last - start).to_i / 7) + 1
    (0...weeks).filter_map do |week|
      week_start = start + week * 7
      week_end = week_start + 6
      first_of_month = Date.new(week_end.year, week_end.month, 1)
      [ week, first_of_month.strftime("%b") ] if first_of_month.between?(week_start, week_end)
    end
  end

  # The views a goal actually stacks: its chosen set, or the shape's natural
  # view when none are picked; a ring without a target degrades to the plain
  # total. Shared by the tile partial and the layout (a stack containing the
  # heatmap spans the full grid row).
  def goal_resolved_displays(goal)
    displays = goal.displays.presence || [ goal.rate? ? "ring" : goal.target ? "bar" : "total" ]
    displays.map { |d| d == "ring" && goal.target.nil? ? "total" : d }.uniq
  end

  PERIOD_PHRASE = { "day" => "today", "week" => "this week", "month" => "this month" }.freeze
  PERIOD_RESET  = { "day" => "resets daily", "week" => "resets Monday", "month" => "resets monthly" }.freeze

  def goal_period_phrase(goal) = PERIOD_PHRASE[goal.per]
  def goal_period_reset(goal)  = PERIOD_RESET[goal.per]

  # The rate goal's completion ring (Strava-style): current period only.
  def goal_stat_ring(percent, radius: 26)
    circumference = 2 * Math::PI * radius
    box = (radius + 6) * 2
    tag.svg viewBox: "0 0 #{box} #{box}", class: "goal-stat__ring", "aria-hidden": true do
      safe_join [
        tag.circle(cx: box / 2, cy: box / 2, r: radius, fill: "none", class: "goal-stat__ring-track"),
        tag.circle(cx: box / 2, cy: box / 2, r: radius, fill: "none", class: "goal-stat__ring-fill",
                   "stroke-dasharray": "#{(circumference * percent / 100.0).round(1)} #{circumference.round(1)}",
                   transform: "rotate(-90 #{box / 2} #{box / 2})"),
        tag.text("#{percent}%", x: box / 2, y: box / 2 + 5, "text-anchor": "middle", class: "goal-stat__ring-text")
      ]
    end
  end

  # The calendar display: this month's day cells, filled where the goal saw
  # a tally (750words-style — history as a quiet fact, no streak counting).
  def goal_month_cells(goal)
    range = Time.zone.today.beginning_of_month..Time.zone.today.end_of_month
    series = goal.daily_series(range)
    safe_join(range.to_a.zip(series).map do |date, amount|
      tag.span date.day, class: "goal-history__day#{" goal-history__day--logged" if amount.positive?}",
               title: "#{date.iso8601} — #{number_with_delimiter(amount)}"
    end)
  end

  # Trailing-window average of a daily series (the "90-day Rolling" line).
  def rolling_average(values, window: 7)
    values.each_index.map do |i|
      slice = values[[ i - window + 1, 0 ].max..i]
      (slice.sum.to_f / slice.size).round
    end
  end

  # Mini bar chart (the week tiles — one bar per day). Each day column carries
  # an invisible full-height hover target with a native <title> popup
  # ("Wed — 1,150"), so zero days are hoverable too.
  def goal_stat_bars(values, labels: WEEKDAY_LABELS, width: 120, height: 36)
    max = values.max.to_f
    bar_width = width.to_f / values.size
    tag.svg viewBox: "0 0 #{width} #{height}", class: "goal-stat__chart",
            preserveAspectRatio: "none", "aria-hidden": true do
      safe_join(values.each_with_index.map do |value, i|
        x = (i * bar_width + 1).round(1)
        bar_height = max.zero? ? 0 : (value / max * (height - 2)).round(1)
        safe_join [
          tag.rect(x: x, y: 0, width: (bar_width - 2).round(1), height: height,
                   class: "goal-stat__hover") { tag.title("#{labels[i]} — #{number_with_delimiter(value)}") },
          tag.rect(x: x, y: height - bar_height, width: (bar_width - 2).round(1),
                   height: bar_height, rx: 1)
        ]
      end)
    end
  end

  # Mini line chart (the 90/365-day tiles).
  def goal_stat_line(values, width: 120, height: 36)
    max = values.max.to_f
    step = width.to_f / (values.size - 1)
    points = values.each_with_index.map do |value, i|
      y = height - 1 - (max.zero? ? 0 : value / max * (height - 2))
      "#{(i * step).round(1)},#{y.round(1)}"
    end
    tag.svg viewBox: "0 0 #{width} #{height}", class: "goal-stat__chart goal-stat__chart--line",
            preserveAspectRatio: "none", "aria-hidden": true do
      tag.polyline points: points.join(" "), fill: "none"
    end
  end
end
