# Standing pages (About, Privacy, Terms, Newsletter) as versions on the
# Record spine — the Publishable column set minus the post-only extras. The
# slug isn't here: it's identity, so it lives on the record (see
# AddSlugToRecords).
class CreatePages < ActiveRecord::Migration[8.2]
  def change
    create_table :pages do |t|
      t.string :title, null: false
      t.string :status, null: false, default: "drafted"
      t.datetime :published_at
      t.datetime :pinned_at
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.integer :body_id, null: false
      t.string :event, null: false, default: "created"
      t.timestamps
      t.index :record_id
      t.index :creator_id
      t.index :body_id
    end
  end
end
