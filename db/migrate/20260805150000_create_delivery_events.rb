# The canonical delivery-event ledger (one row per ESP notification, in a
# provider-agnostic vocabulary) plus dispatch correlation: the provider and its
# message id stamped on each delivery at send time, so a webhook event can be
# attributed to the exact send that caused it.
class CreateDeliveryEvents < ActiveRecord::Migration[8.2]
  def change
    create_table :delivery_events do |t|
      t.string :provider, null: false            # postmark | ses
      t.string :event, null: false               # canonical vocabulary (DeliveryEvent::EVENTS)
      t.string :provider_message_id
      t.string :recipient
      t.references :subscriber
      t.references :delivery, polymorphic: true  # BroadcastDelivery | DropDelivery
      t.json :payload, null: false               # raw provider payload, kept for replay
      t.datetime :occurred_at
      t.datetime :created_at, null: false

      # Both ESPs redeliver (SNS is at-least-once, Postmark retries) — this is
      # the dedupe. NULL message ids don't collide, so unmatched events still land.
      t.index %i[ provider provider_message_id event ], unique: true,
        name: "index_delivery_events_on_dedupe_key"
    end

    add_column :broadcast_deliveries, :provider, :string
    add_column :broadcast_deliveries, :provider_message_id, :string
    add_column :drop_deliveries, :provider, :string
    add_column :drop_deliveries, :provider_message_id, :string
  end
end
