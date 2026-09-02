class CreateBeats < ActiveRecord::Migration[8.2]
  def change
    create_table :beats do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"

      # Which occurrence this beat answers — the date the pulse asked.
      t.date :asked_on, null: false

      t.timestamps
    end

    add_index :beats, [ :record_id, :id ]
    add_index :beats, :creator_id
  end
end
