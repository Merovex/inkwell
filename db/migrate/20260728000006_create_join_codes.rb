class CreateJoinCodes < ActiveRecord::Migration[8.2]
  def change
    # One live, rotatable, multi-use invite code per inviter (root-only until
    # the open-beta switch flips). Signups record who vouched for them.
    create_table :join_codes do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :code, null: false, index: { unique: true }
      t.datetime :rotated_at
      t.timestamps
    end

    add_reference :users, :inviter, foreign_key: { to_table: :users }
    add_index :accounts, :name, unique: true
  end
end
