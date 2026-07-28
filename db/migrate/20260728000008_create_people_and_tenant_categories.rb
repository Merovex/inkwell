class CreatePeopleAndTenantCategories < ActiveRecord::Migration[8.2]
  def change
    # 1.6: the reader's global identity. One row per email address across
    # every press; a Subscriber becomes a person's per-press membership.
    # email_address stays denormalized on subscribers so delivery code never
    # notices (per the plan).
    create_table :people do |t|
      t.string :email_address, null: false, index: { unique: true }
      t.timestamps
    end

    add_reference :subscribers, :person, null: true, foreign_key: true

    up_only do
      execute <<~SQL
        INSERT INTO people (email_address, created_at, updated_at)
        SELECT DISTINCT email_address, datetime('now'), datetime('now') FROM subscribers
      SQL
      execute <<~SQL
        UPDATE subscribers SET person_id =
          (SELECT id FROM people WHERE people.email_address = subscribers.email_address)
      SQL
    end

    change_column_null :subscribers, :person_id, false
    # One membership per person per press — the global email lock dies here.
    remove_index :subscribers, :email_address, unique: true
    add_index :subscribers, [ :person_id, :account_id ], unique: true
    add_index :subscribers, :email_address

    # Categories are per-press (each press names its own board categories).
    add_reference :categories, :account, null: true, foreign_key: true

    up_only do
      execute "UPDATE categories SET account_id = (SELECT MIN(id) FROM accounts)"
    end

    change_column_null :categories, :account_id, false
    remove_index :categories, :name, unique: true
    add_index :categories, [ :account_id, :name ], unique: true
  end
end
