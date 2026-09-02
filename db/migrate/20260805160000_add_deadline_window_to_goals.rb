# The deadline window for project goals — "50,000 words by Nov 30" — behind
# the NaNo-style pace line. starts_on is the optional explicit anchor; blank
# derives from the first tally (Goal#pace_start).
class AddDeadlineWindowToGoals < ActiveRecord::Migration[8.2]
  def change
    add_column :goals, :starts_on, :date
    add_column :goals, :ends_on, :date
  end
end
