# One display per goal grows into a set: `displays` (JSON array, canonical
# order) replaces `display` + the heat_map boolean — "heatmap" was already a
# display AND a toggle, which this unifies. A goal may now stack several views
# (ring + rolling + heatmap); empty still means auto-by-shape.
class GoalDisplaysBecomeASet < ActiveRecord::Migration[8.2]
  class MigratedGoal < ActiveRecord::Base
    self.table_name = "goals"
  end

  def up
    add_column :goals, :displays, :text, null: false, default: "[]"
    MigratedGoal.reset_column_information
    MigratedGoal.find_each do |goal|
      set = []
      set << goal.display if goal.display.present?
      set << "heatmap" if goal.heat_map? && !set.include?("heatmap")
      goal.update_columns(displays: set.to_json)
    end
    remove_column :goals, :display
    remove_column :goals, :heat_map
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
