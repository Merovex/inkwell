class AddCloudflareStatusToCustomDomains < ActiveRecord::Migration[8.2]
  def change
    add_column :custom_domains, :cloudflare_status, :string
  end
end
