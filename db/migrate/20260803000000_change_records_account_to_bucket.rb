# The spine stops belonging to an Account and starts belonging to a *bucket* —
# a polymorphic owner that is an Account today and a Circle tomorrow (the
# Basecamp bucket/recording shape). Every existing record is an Account's, so
# the backfill stamps bucket_type = 'Account', bucket_id = the old account_id.
# No FK constraint (polymorphic); isolation stays with the query-level tenancy
# guard and the Current.bucket scoping discipline.
class ChangeRecordsAccountToBucket < ActiveRecord::Migration[8.0]
  def up
    add_column :records, :bucket_type, :string
    add_column :records, :bucket_id, :integer
    execute "UPDATE records SET bucket_type = 'Account', bucket_id = account_id"
    change_column_null :records, :bucket_type, false
    change_column_null :records, :bucket_id, false

    add_index :records, [ :bucket_type, :bucket_id, :recordable_type ],
      name: "index_records_on_bucket_and_recordable_type"
    remove_index :records, name: "index_records_on_account_id_and_recordable_type"
    remove_column :records, :account_id
  end

  def down
    add_column :records, :account_id, :integer
    execute "UPDATE records SET account_id = bucket_id WHERE bucket_type = 'Account'"
    change_column_null :records, :account_id, false

    add_index :records, [ :account_id, :recordable_type ],
      name: "index_records_on_account_id_and_recordable_type"
    remove_index :records, name: "index_records_on_bucket_and_recordable_type"
    remove_column :records, :bucket_type
    remove_column :records, :bucket_id
  end
end
