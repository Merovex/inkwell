# Each account owns its Turnstile widget (bot-protection plan): the keys are
# indexed on the account row from day one, so widget sharding is data entry,
# never a schema change. Stamped by TurnstileConnection.provision.
class AddTurnstileWidgetToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :turnstile_site_key, :string
    add_column :accounts, :turnstile_secret_key, :string
  end
end
