# Per-goal presentation choices: how the progress tile renders (null = auto
# by shape; ring / pace / last30), and whether the goal shows its GitHub-style
# contribution map on the index.
class AddDisplayToGoals < ActiveRecord::Migration[8.2]
  def change
    add_column :goals, :display, :string
    add_column :goals, :heat_map, :boolean, null: false, default: false
  end
end
