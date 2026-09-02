# Cloudflare lists every outstanding DV TXT record, not one: a rotated order
# leaves the old and the new both pending, and the certificate issues only once
# all of them are published. A single txt_name/txt_value pair could hold just
# the first, so the record actually blocking issuance stayed invisible to the
# author (observed on benwilsondev.com, 2026-08-26).
class ReplaceCustomDomainTxtWithValidationRecords < ActiveRecord::Migration[8.2]
  def change
    add_column :custom_domains, :validation_records, :json, default: [], null: false

    # Deliberately not backfilled: the stored pair is the stale token that
    # caused the bug. The next poll writes the live set.
    remove_column :custom_domains, :txt_name, :string
    remove_column :custom_domains, :txt_value, :string
  end
end
