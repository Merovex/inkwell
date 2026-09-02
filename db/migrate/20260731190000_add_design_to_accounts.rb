# The public site's saved design (the SiteDesigner's working payload). One
# JSON blob per account — validated by SiteDesign before it's written.
class AddDesignToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :design, :text
  end
end
