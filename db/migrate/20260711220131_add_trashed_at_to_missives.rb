class AddTrashedAtToMissives < ActiveRecord::Migration[8.2]
  def change
    add_column :missives, :trashed_at, :datetime
  end
end
