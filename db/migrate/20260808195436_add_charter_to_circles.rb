class AddCharterToCircles < ActiveRecord::Migration[8.2]
  def change
    add_column :circles, :charter, :text
  end
end
