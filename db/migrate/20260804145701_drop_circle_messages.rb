class DropCircleMessages < ActiveRecord::Migration[8.2]
  # Circle discussions are now plain Messages owned by a Circle bucket (the same
  # class the site forum uses), so the parallel circle_messages table goes away.
  # Unused in production — nothing to migrate.
  def up
    drop_table :circle_messages
  end

  def down
    create_table :circle_messages do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"
      t.string :title
      t.timestamps
      t.index [ :record_id, :id ], name: "index_circle_messages_on_record_id_and_id"
      t.index :creator_id, name: "index_circle_messages_on_creator_id"
    end
  end
end
