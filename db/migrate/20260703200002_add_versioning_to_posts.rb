class AddVersioningToPosts < ActiveRecord::Migration[8.2]
  # Posts become immutable, event-tagged versions (ADR 0007): each row carries a
  # back-pointer to its record, the creator of that version, the event that
  # produced it, and a reference to a shareable Body for its rich text.
  def up
    add_reference :posts, :record, foreign_key: true
    add_reference :posts, :creator, foreign_key: { to_table: :users }
    add_reference :posts, :body, foreign_key: true
    add_column :posts, :event, :string, null: false, default: "created"
    add_index :posts, [ :record_id, :id ]

    backfill_existing_posts

    change_column_null :posts, :record_id, false
    change_column_null :posts, :creator_id, false
    change_column_null :posts, :body_id, false
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private
    # Existing posts predate versioning: point each at its record and creator,
    # and move its rich text onto a freshly minted Body.
    def backfill_existing_posts
      select_all("SELECT id, recordable_id, creator_id FROM records WHERE recordable_type = 'Post'").each do |row|
        execute "INSERT INTO bodies (created_at, updated_at) VALUES (datetime('now'), datetime('now'))"
        body_id = select_value("SELECT last_insert_rowid()")

        execute <<~SQL
          UPDATE posts
          SET record_id = #{row['id']}, creator_id = #{row['creator_id']}, body_id = #{body_id}
          WHERE id = #{row['recordable_id']}
        SQL
        execute <<~SQL
          UPDATE action_text_rich_texts
          SET record_type = 'Body', record_id = #{body_id}
          WHERE record_type = 'Post' AND record_id = #{row['recordable_id']}
        SQL
      end
    end
end
