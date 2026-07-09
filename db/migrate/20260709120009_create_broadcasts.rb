class CreateBroadcasts < ActiveRecord::Migration[8.2]
  def change
    # One email send of a post to confirmed subscribers (HEY World style). Hangs
    # off the post's Record (the stable identity, not a version) — so it survives
    # edits and the unique index makes the send strictly one-time per post. Its
    # existence is the guard; sent_at/recipients_count record the outcome.
    create_table :broadcasts do |t|
      t.integer :record_id, null: false
      t.datetime :sent_at
      t.integer :recipients_count, null: false, default: 0
      t.timestamps

      t.index :record_id, unique: true
    end
  end
end
