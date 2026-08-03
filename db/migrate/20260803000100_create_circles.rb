# A Circle — the second kind of bucket on the spine. Author-owned (a User, not
# an Account), size-capped, with its own slug namespace under /circles. It owns
# Records exactly as an Account does; membership is people, tracked separately
# from account_users because the role/size semantics differ.
class CreateCircles < ActiveRecord::Migration[8.0]
  def change
    create_table :circles do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.integer :owner_id, null: false            # the User who owns the circle
      t.integer :member_limit                      # nil = uncapped for now
      t.timestamps
    end
    add_index :circles, :slug, unique: true
    add_index :circles, :owner_id

    create_table :circle_memberships do |t|
      t.integer :circle_id, null: false
      t.integer :user_id, null: false
      t.string  :role, null: false, default: "member"
      t.timestamps
    end
    add_index :circle_memberships, [ :circle_id, :user_id ], unique: true
    add_index :circle_memberships, :user_id
  end
end
