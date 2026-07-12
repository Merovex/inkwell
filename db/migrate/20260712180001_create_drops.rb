class CreateDrops < ActiveRecord::Migration[8.2]
  def change
    # One email in a Drip's sequence — a recordable (its Lexxy body is versioned
    # like a Comment). Ordered within the Drip by its Record.position; delay_days
    # is the absolute send offset (in days) from the subscriber's confirmed_at,
    # so 0 means "right after confirmation".
    create_table :drops do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string  :event, default: "created", null: false
      t.string  :subject, null: false
      t.integer :delay_days, default: 0, null: false
      t.timestamps
    end

    add_index :drops, [ :record_id, :id ]
    add_index :drops, :creator_id
  end
end
