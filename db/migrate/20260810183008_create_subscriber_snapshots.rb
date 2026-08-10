class CreateSubscriberSnapshots < ActiveRecord::Migration[8.2]
  def change
    create_table :subscriber_snapshots do |t|
      t.references :account, null: false, foreign_key: true
      # The Monday the week starts on — one snapshot per account per week.
      t.date :week_of, null: false
      # Sendable (confirmed, non-seed) count at capture; the trend line.
      t.integer :confirmed_count, null: false, default: 0
      # That week's movement, kept for history alongside the standing total.
      t.integer :joined_count, null: false, default: 0
      t.integer :unsubscribed_count, null: false, default: 0

      t.timestamps
    end

    add_index :subscriber_snapshots, [ :account_id, :week_of ], unique: true
  end
end
