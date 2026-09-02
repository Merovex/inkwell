# One table, one meaning: a Download is a redeemed fetch of a magnet file.
# Grant present = the tokened claim flow; grant absent = the ungated direct
# link. Every row now carries the magnet, so per-magnet stats are one query
# across both doors (existing rows backfill through their grant).
class AllowGrantlessDownloads < ActiveRecord::Migration[8.2]
  def up
    add_column :downloads, :magnet_id, :integer
    execute <<~SQL
      UPDATE downloads
      SET magnet_id = (SELECT magnet_id FROM grants WHERE grants.id = downloads.grant_id)
    SQL
    change_column_null :downloads, :magnet_id, false
    change_column_null :downloads, :grant_id, true
    add_index :downloads, :magnet_id
  end

  def down
    Download.where(grant_id: nil).delete_all
    remove_index :downloads, :magnet_id
    remove_column :downloads, :magnet_id
    change_column_null :downloads, :grant_id, false
  end
end
