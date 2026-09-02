class CreatePulseSubscriptions < ActiveRecord::Migration[8.2]
  def change
    create_table :pulse_subscriptions do |t|
      # The pulse's stable Record identity (survives edits to the question).
      t.integer :pulse_record_id, null: false
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :pulse_subscriptions, [ :pulse_record_id, :user_id ], unique: true
  end
end
