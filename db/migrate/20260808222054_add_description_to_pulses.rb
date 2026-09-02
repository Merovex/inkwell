class AddDescriptionToPulses < ActiveRecord::Migration[8.2]
  def change
    add_column :pulses, :description, :string
  end
end
