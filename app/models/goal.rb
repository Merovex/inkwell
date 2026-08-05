# An author's personal practice target — "Draft the novel", measured in words,
# hours, or pages. Lives on the Record spine bucketed to the USER, not a site
# or circle: you carry your goals with you across every room (circles could
# reference one later, but it is always yours alone). Mutable — edits amend in
# place, no version history, no publish states; the spine is here for identity,
# trash, and the Tally threading, not ceremony.
class Goal < ApplicationRecord
  include Recordable

  UNITS    = %w[ words hours pages ].freeze
  PERIODS  = %w[ day week month ].freeze
  # Progress views the author can pick — a SET, stacked on the card in this
  # canonical order (the now-number first, trends, then history). Empty =
  # auto by shape (rate → ring, project → bar, logbook → plain total).
  DISPLAYS = %w[ ring pace rolling last30 calendar heatmap ].freeze

  validates :title, presence: true
  validates :unit, inclusion: { in: UNITS }
  validates :target, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  # Shape: target + per. per: nil with a target = a project ("50,000 in
  # total"); per: day/week/month = a rate ("2,000 per day") and then the
  # target is required — a rate without a number is meaningless. No target at
  # all = a plain logbook.
  normalizes :per, with: -> { it.presence }
  validates :per, inclusion: { in: PERIODS }, allow_nil: true
  # The intersection both sanitizes (junk and blanks drop) and imposes the
  # canonical stacking order, whatever order the checkboxes arrived in.
  serialize :displays, coder: JSON, type: Array
  normalizes :displays, with: -> { DISPLAYS & Array(it) }
  # The coder stores an empty set as NULL; the reader keeps the contract Array.
  def displays = super || []
  validates :target, presence: { message: "is required for a rate (per day/week/month) goal" }, if: -> { per.present? }

  def rate?    = per.present?
  def project? = per.nil? && target.present?

  # No draft state and nothing published — an amend is just a correction.
  def mutable? = true

  # The goal's reports: current versions of the child Tally records (parent =
  # this goal's Record — the same threading Beats use), newest day first.
  def tallies
    Tally.current_in(Record.active, parent: record_id).order(logged_on: :desc, record_id: :desc)
  end

  def total = tallies.sum(:amount)

  # What this goal measures. A project/logbook measures its own tallies (the
  # attribution: these words went HERE). A rate goal owns nothing — it
  # observes every tally in its unit across the owner's goals, so "2,000
  # words/day" credits novel words and blog words alike.
  def observed_tallies
    return tallies unless rate?

    unit_goal_record_ids = Goal.current_in(Record.active.where(bucket: record.bucket))
      .where(unit: unit).select(:record_id)
    Tally.current_in(Record.active, parent: unit_goal_record_ids)
  end

  # The current period's window (nil for non-rate goals).
  def period_range(today = Time.zone.today)
    case per
    when "day"   then today..today
    when "week"  then today.beginning_of_week..today.end_of_week
    when "month" then today.beginning_of_month..today.end_of_month
    end
  end

  def period_total = observed_tallies.where(logged_on: period_range).sum(:amount)

  # Per-day sums over a date range, zero-filled — the raw series behind every
  # progress tile and heat strip (GoalsHelper draws; this measures).
  def daily_series(range)
    sums = observed_tallies.where(logged_on: range).group(:logged_on).sum(:amount)
    range.to_a.map { |date| sums[date] || 0 }
  end

  # Progress toward the target, capped at 100 (overshooting stays "done").
  # Projects measure lifetime total; rates measure the current period.
  def completion_percent
    logged = rate? ? period_total : total
    ((logged.to_f / target) * 100).clamp(0, 100).round
  end

  # Calendar years before this one that hold tallies — each earns its own
  # heat strip on the heatmap card, GH-style. Newest first.
  def earlier_tally_years
    observed_tallies.distinct.pluck(:logged_on).map(&:year).uniq
      .select { |year| year < Time.zone.today.year }.sort.reverse
  end
end
