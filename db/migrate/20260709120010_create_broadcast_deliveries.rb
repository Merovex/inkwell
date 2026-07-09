class CreateBroadcastDeliveries < ActiveRecord::Migration[8.2]
  def change
    # One row per (broadcast, subscriber): who a post was emailed to, and when.
    # The unique index makes the fan-out idempotent and resumable — a retried
    # job skips anyone already stamped instead of re-mailing them.
    create_table :broadcast_deliveries do |t|
      t.references :broadcast, null: false, foreign_key: true
      t.references :subscriber, null: false, foreign_key: true
      t.datetime :sent_at
      t.datetime :created_at, null: false

      t.index [ :broadcast_id, :subscriber_id ], unique: true
    end
  end
end
