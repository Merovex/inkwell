class AddArchivedAtToRecords < ActiveRecord::Migration[8.2]
  def change
    add_column :records, :archived_at, :datetime
  end
end
