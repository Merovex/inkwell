class AddScheduledAtToBroadcasts < ActiveRecord::Migration[8.2]
  def change
    # When set, the send is deferred to this time via a wait_until job (mirrors
    # a post's scheduled publish). Null ⇒ send immediately. Cleared of meaning
    # once sent_at is stamped.
    add_column :broadcasts, :scheduled_at, :datetime
  end
end
