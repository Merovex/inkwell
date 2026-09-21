class AllowDuplicateAccountNames < ActiveRecord::Migration[8.2]
  # accounts.name is a private label (the account picker, the site switcher);
  # a site's identity is its slug, handle, and domain, which all stay unique.
  # Global uniqueness on the label only meant one author's "Jane Smith Books"
  # blocked the next — and told them someone else was here. The public
  # site_name was never unique.
  def change
    remove_index :accounts, :name, unique: true
    add_index :accounts, :name
  end
end
