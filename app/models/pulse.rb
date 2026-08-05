# A circle's recurring check-in: a question asked to subscribed members on a
# cadence, whose answers (Beats) hang off this pulse's Record. A recordable — its
# rows are the versions of a Record — so edits to the question/schedule and
# activate/deactivate land as tracked history, owned by the circle bucket.
# Members subscribe themselves (PulseSubscription); Beats thread to the pulse
# like comments thread to a post.
class Pulse < ApplicationRecord
  include Recordable

  CADENCES = %w[ daily weekly biweekly monthly ].freeze
  WEEKDAYS = %w[ Sunday Monday Tuesday Wednesday Thursday Friday Saturday ].freeze

  # Who's being asked — the circle members who've opted in, keyed to the stable
  # Record identity so the roster survives edits to the question.
  has_many :subscriptions, class_name: "PulseSubscription",
    primary_key: :record_id, foreign_key: :pulse_record_id, dependent: :destroy
  has_many :respondents, through: :subscriptions, source: :user

  validates :question, presence: true
  validates :cadence, inclusion: { in: CADENCES }
  validates :ask_at_minutes, inclusion: { in: 0..1439 }

  scope :current, -> { current_in(Record.active) }
  scope :live,    -> { current.where(active: true) }

  # Every version is history — activating/deactivating and question edits land
  # as new versions (same choice as Drip).
  def mutable? = false

  # The answers to this pulse: current versions of the child Beat records
  # (parent = this pulse's Record), newest occurrence first then by author.
  def beats
    Beat.current_in(Record.active, parent: record_id)
      .includes(:record, :rich_text_content, creator: { avatar_attachment: :blob })
      .order(asked_on: :desc, record_id: :asc)
  end

  # The beats for one occurrence (a given ask date).
  def beats_on(date) = beats.where(asked_on: date)

  def subscribed?(user) = user.present? && subscriptions.exists?(user_id: user.id)

  # Enroll a batch (circle members at setup — everyone's in by default): one
  # statement, no per-member ceremony. Membership is a given at this point.
  def subscribe(users)
    PulseSubscription.insert_all(users.ids.map { |user_id| { pulse_record_id: record_id, user_id: user_id } })
  end

  # The occurrence members are currently answering — the latest ask (nil until
  # the pulse has first fired).
  def current_occurrence = last_asked_on

  # Is this pulse due to ask on `date`, per its cadence? daily/weekly fire on the
  # selected weekday(s); biweekly on those weekdays in even ISO weeks; monthly on
  # the first occurrence of the selected weekday in the month (e.g. first Monday).
  def due_on?(date)
    case cadence
    when "daily", "weekly" then weekday_selected?(date)
    when "biweekly"        then weekday_selected?(date) && date.cweek.even?
    when "monthly"         then weekday_selected?(date) && date.day <= 7
    else false
    end
  end

  def weekday_selected?(date) = days_of_week.anybits?(1 << date.wday)

  # The chosen weekday names, in week order ("Monday", "Wednesday").
  def selected_day_names
    WEEKDAYS.each_index.select { |wday| days_of_week.anybits?(1 << wday) }.map { |wday| WEEKDAYS[wday] }
  end

  # Fire the pulse for `on`: email every subscribed member and stamp the ask.
  # last_asked_on is operational state, not a content edit, so it's set in place
  # (no new version) — dup carries it forward if the question is later revised.
  def ask!(on = Time.zone.today)
    respondents.find_each do |user|
      PulseMailer.ask(self, user, on).deliver_later
      # The ask is also a bell notification; the email above is its "email
      # channel", so the kind stays out of the digest (no double asks).
      Notification.deliver(record, to: user, kind: "pulse_asked")
    end
    update_column(:last_asked_on, on)
  end

  # "4:30 PM" — a minutes-past-midnight value as a plain label (no zone).
  def self.time_label(minutes)
    hour, minute = minutes.divmod(60)
    suffix = hour < 12 ? "AM" : "PM"
    hour12 = (hour % 12).zero? ? 12 : hour % 12
    format("%d:%02d %s", hour12, minute, suffix)
  end

  def ask_at = self.class.time_label(ask_at_minutes)

  # "Mondays and Wednesdays", "the first Monday of each month" — a human summary.
  def schedule_summary
    days = selected_day_names
    case cadence
    when "monthly"  then "the first #{days.to_sentence} of each month"
    when "biweekly" then "every other #{days.map(&:pluralize).to_sentence}"
    else days.map(&:pluralize).to_sentence.presence || cadence
    end
  end
end
