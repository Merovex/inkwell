class ReplaceCompleteWithStateOnSeries < ActiveRecord::Migration[8.2]
  def change
    remove_column :series, :complete, :boolean, default: false, null: false
    add_column :series, :state, :string, default: "in_progress", null: false
  end
end
