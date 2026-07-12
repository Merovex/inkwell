class AddCountryCodeToAhoyVisits < ActiveRecord::Migration[8.2]
  def change
    add_column :ahoy_visits, :country_code, :string
  end
end
