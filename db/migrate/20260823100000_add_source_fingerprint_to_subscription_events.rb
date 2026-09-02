# The consent log gains a keyed fingerprint of each event's IP neighborhood
# (SubscriptionEvent.fingerprint, ADR 0026) — the cross-site "same source?"
# signal, kept apart from the raw ip_address so the two can have different
# lives. Backfilled from the raw IPs still on the rows; update_columns because
# the model's before_update guard (append-only) rightly refuses update!.
class AddSourceFingerprintToSubscriptionEvents < ActiveRecord::Migration[8.2]
  def up
    add_column :subscription_events, :source_fingerprint, :string
    add_index :subscription_events, :source_fingerprint

    SubscriptionEvent.reset_column_information
    SubscriptionEvent.where.not(ip_address: [ nil, "" ]).find_each do |event|
      event.update_columns(source_fingerprint: SubscriptionEvent.fingerprint(event.ip_address))
    end
  end

  def down
    remove_index :subscription_events, :source_fingerprint
    remove_column :subscription_events, :source_fingerprint
  end
end
