class CreateSettings < ActiveRecord::Migration[8.2]
  def change
    # Install-wide configuration — a singleton (one row, fetched as
    # Setting.current). Holds the public Merovex Press identity today; when the
    # multi-tenancy account_id work lands, these columns move onto Account.
    # The logo is an Active Storage attachment and the description is Action
    # Text, so neither has a column here.
    create_table :settings do |t|
      t.string :site_name
      t.string :tagline
      t.string :contact_email
      t.timestamps
    end
  end
end
