class CreateAccountUsers < ActiveRecord::Migration[8.2]
  def change
    create_table :account_users do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :account_users, [ :account_id, :user_id ], unique: true

    # Membership only — no role column until per-account roles are a real
    # feature (ADR 0017). Every existing user joins the first account.
    up_only do
      execute <<~SQL
        INSERT INTO account_users (account_id, user_id, created_at, updated_at)
        SELECT (SELECT MIN(id) FROM accounts), users.id, datetime('now'), datetime('now')
        FROM users
        WHERE EXISTS (SELECT 1 FROM accounts)
      SQL
    end
  end
end
