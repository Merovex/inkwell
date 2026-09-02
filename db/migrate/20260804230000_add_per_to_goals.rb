# A goal's shape: target + per. Null per with a target = a project ("50,000
# words in total"); day/week/month = a rate ("2,000 words per day"); no target
# at all = a plain logbook. Existing goals keep null = unchanged behavior.
class AddPerToGoals < ActiveRecord::Migration[8.2]
  def change
    add_column :goals, :per, :string
  end
end
