class AddAccountToAudience < ActiveRecord::Migration[8.2]
  def change
    # Subscribers belong to the press they subscribed to. (The email-unique
    # index stays GLOBAL until 1.6's person split — one address can't yet
    # subscribe to two presses; a known, accepted interim limit.)
    add_reference :subscribers, :account, null: true, index: false

    # Visits stamp the tenant whose public site was visited; nullable because
    # app-host traffic (sign-in, picker) belongs to no tenant's dashboard.
    add_reference :ahoy_visits, :account, null: true

    up_only do
      execute "UPDATE subscribers SET account_id = (SELECT MIN(id) FROM accounts)"
      execute "UPDATE ahoy_visits SET account_id = (SELECT MIN(id) FROM accounts)"
    end

    change_column_null :subscribers, :account_id, false
    add_index :subscribers, [ :account_id, :status ]
    add_foreign_key :subscribers, :accounts
    add_foreign_key :ahoy_visits, :accounts
  end
end
