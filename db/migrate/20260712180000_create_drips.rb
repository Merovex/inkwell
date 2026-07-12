class CreateDrips < ActiveRecord::Migration[8.2]
  def change
    # A drip campaign — a recordable, so each row is a version of a Record.
    # `active` gates whether new subscribers enroll; `trigger` anchors the
    # schedule (subscriber confirmation, for now).
    create_table :drips do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string  :event, default: "created", null: false
      t.string  :title, null: false
      t.boolean :active, default: false, null: false
      t.string  :trigger, default: "confirmed", null: false
      t.timestamps
    end

    add_index :drips, [ :record_id, :id ]
    add_index :drips, :creator_id
  end
end
