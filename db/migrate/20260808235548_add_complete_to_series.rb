class AddCompleteToSeries < ActiveRecord::Migration[8.2]
  def change
    add_column :series, :complete, :boolean, default: false, null: false
  end
end
