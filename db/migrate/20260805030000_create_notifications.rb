# "A person did something that concerns you" — the bell's rows. Off the
# Record spine (plumbing, not content): sources destroy their notifications
# with them, read ones get pruned, no history ceremony.
class CreateNotifications < ActiveRecord::Migration[8.2]
  def change
    create_table :notifications do |t|
      t.integer :user_id, null: false     # the recipient
      t.string :source_type, null: false  # what happened (CircleInvitation, …)
      t.integer :source_id, null: false
      t.string :kind, null: false         # invited, invitation_accepted, …
      t.datetime :read_at

      t.timestamps
    end
    add_index :notifications, [ :user_id, :read_at ]
    add_index :notifications, [ :source_type, :source_id ]
  end
end
