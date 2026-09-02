class AddDescriptionToCircles < ActiveRecord::Migration[8.2]
  def change
    add_column :circles, :description, :text
  end
end
