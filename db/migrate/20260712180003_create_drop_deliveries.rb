class CreateDropDeliveries < ActiveRecord::Migration[8.2]
  def change
    # One row per (stream, drop): whether a Drop was sent to a subscriber or
    # skipped, plus SES engagement milestones (mirrors broadcast_deliveries).
    # The unique [stream, drop] index makes the send tick idempotent — a re-run
    # never re-sends a Drop.
    create_table :drop_deliveries do |t|
      t.references :stream, null: false, foreign_key: true
      t.references :drop_record, null: false, foreign_key: { to_table: :records }
      t.references :subscriber, null: false, foreign_key: true
      t.string   :status, default: "pending", null: false
      t.string   :skip_reason
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.datetime :bounced_at
      t.datetime :complained_at
      t.datetime :unsubscribed_at
      t.timestamps

      t.index [ :stream_id, :drop_record_id ], unique: true
    end
  end
end
