class AddAccountToSpine < ActiveRecord::Migration[8.2]
  def change
    # Every recordable inherits tenancy through its record row (ADR 0017);
    # missives sit off the spine and carry their own column. Backfill puts
    # all existing content in the first account (the Merovex cut-in).
    add_reference :records, :account, null: true, index: false
    add_reference :missives, :account, null: true

    up_only do
      execute "UPDATE records  SET account_id = (SELECT MIN(id) FROM accounts)"
      execute "UPDATE missives SET account_id = (SELECT MIN(id) FROM accounts)"
    end

    change_column_null :records, :account_id, false
    change_column_null :missives, :account_id, false

    add_index :records, [ :account_id, :recordable_type ]
    add_foreign_key :records, :accounts
    add_foreign_key :missives, :accounts
  end
end
