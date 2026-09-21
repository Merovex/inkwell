class CreateExports < ActiveRecord::Migration[8.2]
  def change
    # An author's request for a copy of their site (Export) — a recordable,
    # bucketed to the Account. The zip itself rides Active Storage.
    create_table :exports do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"

      # pending → built | failed (Export::STATUSES).
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at
      # The archive carries the subscriber list, so fetches are counted.
      t.integer :downloads_count, null: false, default: 0
      t.datetime :last_downloaded_at

      t.timestamps
    end
    add_index :exports, [ :record_id, :id ]
    add_index :exports, :creator_id
  end
end
