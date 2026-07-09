class CreateSubscriptionEvents < ActiveRecord::Migration[8.2]
  def change
    # The append-only consent log: one immutable row per state transition
    # (subscribed / confirmed / unsubscribed / resubscribed), each stamped with
    # when, from where, and the IP. This is the legal proof-of-consent trail —
    # rows are written, never updated. Only created_at (no updated_at), since an
    # event never changes. See ADR 0011.
    create_table :subscription_events do |t|
      t.references :subscriber, null: false, foreign_key: true
      t.string :action, null: false
      t.string :ip_address
      t.string :source
      t.datetime :created_at, null: false
    end
  end
end
