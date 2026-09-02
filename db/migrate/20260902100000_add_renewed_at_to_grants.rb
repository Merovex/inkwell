# A renewal ("send me a new link", reader-requested or staff-sent) has to
# restore the download allowance as well as mint a fresh token — otherwise the
# new link opens the same expired page the reader wrote in about. The allowance
# moves rather than the Downloads being deleted: those rows are the audit trail
# that replaces a counter column (see CreateMagnets), so they must survive.
# NULL means never renewed, and the grant counts from its own created_at.
class AddRenewedAtToGrants < ActiveRecord::Migration[8.2]
  def change
    add_column :grants, :renewed_at, :datetime
  end
end
