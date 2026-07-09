class AddEngagementToBroadcastDeliveries < ActiveRecord::Migration[8.2]
  def change
    # Per-recipient engagement milestones, each stamped the first time Mailgun
    # reports it (first-event-wins → unique opens/clicks). The broadcast's cached
    # counters are bumped on that first transition.
    change_table :broadcast_deliveries, bulk: true do |t|
      t.datetime :delivered_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.datetime :bounced_at
      t.datetime :complained_at
      t.datetime :unsubscribed_at
    end
  end
end
