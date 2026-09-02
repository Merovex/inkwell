# A notification must outlive its source: accepting an invitation destroys
# the invitation row, and the "you're invited" announcement was dying with it.
# Each notification now carries its own copy (actor, sentence, door) stamped
# at delivery; the source association loosens to optional and revocation
# removes notifications explicitly (the no-ghosts rule, scoped to revokes).
class NotificationsCarryTheirOwnCopy < ActiveRecord::Migration[8.2]
  def change
    add_column :notifications, :actor_id, :integer
    add_column :notifications, :title, :string
    add_column :notifications, :url, :string
    change_column_null :notifications, :source_type, true
    change_column_null :notifications, :source_id, true
  end
end
