class CreateGoalsAndTallies < ActiveRecord::Migration[8.2]
  def change
    create_table :goals do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"

      t.string :title, null: false
      # The metric base every tally reports in (Goal::UNITS).
      t.string :unit, null: false, default: "words"
      # Optional finish line ("50,000"); absent means an open practice.
      t.integer :target

      t.timestamps
    end
    add_index :goals, [ :record_id, :id ]
    add_index :goals, :creator_id

    create_table :tallies do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"

      t.date :logged_on, null: false
      t.integer :amount, null: false
      # An old tweet's worth of context (140), not a rich-text body.
      t.string :note

      t.timestamps
    end
    add_index :tallies, [ :record_id, :id ]
    add_index :tallies, :creator_id
  end
end
