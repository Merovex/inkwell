# Per-site SES tenancy (docs/email-tenant-byod-plan.md). The tenant NAME is
# derived ("site-#{slug}", slug immutable) — only the provisioning moment is
# persisted. The handle is the author-chosen local part of the shared-lane
# From address (<handle>@kindredquill.email); NULL until claimed.
class AddEmailTenancyToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :ses_tenant_provisioned_at, :datetime
    add_column :accounts, :handle, :string
    add_index :accounts, :handle, unique: true
  end
end
