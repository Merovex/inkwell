# One report against a Goal — a date, an amount in the goal's unit, and an
# old-tweet's worth of note. A recordable whose Record parents to the goal's
# Record; bucketed to the user like the goal itself. Mutable — corrections
# amend in place, no version churn (a tally is a logbook line, not an essay).
class Tally < ApplicationRecord
  include Recordable

  NOTE_MAX_LENGTH = 140 # an old tweet

  before_validation { self.logged_on ||= Time.zone.today }

  validates :logged_on, presence: true
  validates :amount, numericality: { only_integer: true, greater_than: 0 }
  validates :note, length: { maximum: NOTE_MAX_LENGTH }

  def mutable? = true
end
