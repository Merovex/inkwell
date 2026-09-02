# Support tickets — the App's help desk, created in-app (no mail-in). A
# recordable on the spine, bucketed to the requesting USER (the Goals
# pattern); the thread under it is plain Comments. Versioned like a comment:
# status changes are revisions.
class CreateTickets < ActiveRecord::Migration[8.2]
  def change
    create_table :tickets do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"
      t.string :title, null: false
      t.string :status, null: false, default: "open"
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :tickets, :record_id
    add_index :tickets, :creator_id
    add_index :tickets, [ :record_id, :id ]
  end
end
