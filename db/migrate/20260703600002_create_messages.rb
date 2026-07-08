class CreateMessages < ActiveRecord::Migration[8.2]
  def change
    # Fourth recordable on the spine — a message on the board (/forum).
    # Publishable exactly like posts (draft/schedule/publish, Body-backed
    # rich text) plus an optional category. The envelope (creator, parent,
    # trash) lives on the message's Record.
    create_table :messages do |t|
      t.string :title, null: false
      t.string :status, null: false, default: "drafted"
      t.datetime :published_at
      t.datetime :pinned_at
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.integer :body_id, null: false
      t.integer :category_id
      t.string :event, default: "created", null: false
      t.timestamps

      t.index [ :record_id, :id ]
      t.index :record_id
      t.index :creator_id
      t.index :body_id
      t.index :category_id
      t.index [ :status, :published_at ]
    end

    add_foreign_key :messages, :records
    add_foreign_key :messages, :users, column: :creator_id
    add_foreign_key :messages, :bodies
    add_foreign_key :messages, :categories
  end
end
