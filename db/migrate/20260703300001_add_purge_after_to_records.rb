class AddPurgeAfterToRecords < ActiveRecord::Migration[8.2]
  # The trash's deletion deadline, set when trashed: 30 days normally, 2 years
  # for anything that was ever published (legal retention). The purge job
  # destroys records past their deadline.
  def change
    add_column :records, :purge_after, :datetime
    add_index :records, :purge_after
  end
end
