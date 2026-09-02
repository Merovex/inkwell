class CreateSitesAndDropSettings < ActiveRecord::Migration[8.2]
  def up
    create_table :sites do |t|
      t.string  :site_name, null: false
      t.string  :tagline
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string  :event, default: "created", null: false
      t.timestamps
      t.index [ :record_id, :id ]
      t.index :record_id
    end
    add_foreign_key :sites, :records
    add_foreign_key :sites, :users, column: :creator_id

    migrate_settings_to_site
    drop_table :settings
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private
    # The old install-wide Setting singleton becomes the first account's Site:
    # a record row on the spine, the site row as its current version, and the
    # Setting-keyed rich texts (description, privacy_policy, terms) and logo
    # attachment re-keyed to the Site. Fresh installs (no settings row) skip —
    # Account#site creates on demand.
    def migrate_settings_to_site
      setting = select_one("SELECT * FROM settings ORDER BY id LIMIT 1") or return
      account = select_one("SELECT id, owner_id FROM accounts ORDER BY id LIMIT 1") or return

      execute <<~SQL
        INSERT INTO records (recordable_type, creator_id, account_id, created_at, updated_at)
        VALUES ('Site', #{account["owner_id"]}, #{account["id"]}, datetime('now'), datetime('now'))
      SQL
      record_id = select_value("SELECT last_insert_rowid()")

      execute <<~SQL
        INSERT INTO sites (site_name, tagline, record_id, creator_id, event, created_at, updated_at)
        VALUES (#{connection.quote(setting["site_name"])}, #{connection.quote(setting["tagline"])},
                #{record_id}, #{account["owner_id"]}, 'created', datetime('now'), datetime('now'))
      SQL
      site_id = select_value("SELECT last_insert_rowid()")

      execute "UPDATE records SET recordable_id = #{site_id} WHERE id = #{record_id}"
      execute <<~SQL
        UPDATE action_text_rich_texts SET record_type = 'Site', record_id = #{site_id}
        WHERE record_type = 'Setting' AND record_id = #{setting["id"]}
      SQL
      execute <<~SQL
        UPDATE active_storage_attachments SET record_type = 'Site', record_id = #{site_id}
        WHERE record_type = 'Setting' AND record_id = #{setting["id"]}
      SQL
    end
end
