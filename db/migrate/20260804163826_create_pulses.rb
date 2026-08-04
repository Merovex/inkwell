class CreatePulses < ActiveRecord::Migration[8.2]
  def change
    create_table :pulses do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"

      t.text :question, null: false
      t.string :cadence, null: false, default: "weekly"
      # Bitmask of weekdays for the "daily on…" cadence (bit 0 = Sunday … bit 6 = Saturday).
      t.integer :days_of_week, null: false, default: 0
      # When to ask, as minutes past midnight in the circle's zone (30-min steps).
      t.integer :ask_at_minutes, null: false, default: 540 # 9:00am
      t.boolean :active, null: false, default: true
      t.date :last_asked_on

      t.timestamps
    end

    add_index :pulses, [ :record_id, :id ]
    add_index :pulses, :creator_id
  end
end
