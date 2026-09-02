class CreateCircleInvitations < ActiveRecord::Migration[8.2]
  def change
    create_table :circle_invitations do |t|
      t.integer :circle_id, null: false
      # user_id is the invitee; inviter_id the member who vouched.
      t.integer :user_id, null: false
      t.integer :inviter_id, null: false

      t.timestamps
    end
    # One standing invitation per person per circle; answering it destroys it.
    add_index :circle_invitations, [ :circle_id, :user_id ], unique: true
    add_index :circle_invitations, :user_id
    add_index :circle_invitations, :inviter_id
  end
end
