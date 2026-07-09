class AddMetricsToBroadcasts < ActiveRecord::Migration[8.2]
  def change
    # Cached aggregate metrics for the broadcasts dashboard — bumped once per
    # recipient as their delivery hits each milestone (see BroadcastDelivery),
    # so opens/clicks are unique. recipients_count already exists.
    change_table :broadcasts, bulk: true do |t|
      t.integer :delivered_count,    null: false, default: 0
      t.integer :opened_count,       null: false, default: 0
      t.integer :clicked_count,      null: false, default: 0
      t.integer :bounced_count,      null: false, default: 0
      t.integer :complained_count,   null: false, default: 0
      t.integer :unsubscribed_count, null: false, default: 0
    end
  end
end
