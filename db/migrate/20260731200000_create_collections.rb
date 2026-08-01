# A Collection is a recordable on the spine, Publishable exactly like Series —
# its own table mirroring `series` (reuse via concerns, not STI). Books belong
# via the shared Installment join, keyed by Record id.
class CreateCollections < ActiveRecord::Migration[8.2]
  def change
    create_table :collections do |t|
      t.string :title, null: false
      t.string :status, default: "drafted", null: false
      t.datetime :published_at
      t.datetime :pinned_at
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.integer :body_id, null: false
      t.string :event, default: "created", null: false
      t.integer :author_record_id
      t.timestamps
    end

    add_index :collections, :author_record_id
    add_index :collections, :body_id
    add_index :collections, :creator_id
    add_index :collections, %i[record_id id]
    add_index :collections, :record_id
    add_index :collections, %i[status published_at]
  end
end
