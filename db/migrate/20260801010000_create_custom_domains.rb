# A tenant's connected custom hostnames — one row per hostname (apex AND www
# are separate rows pointing at the same account), tracking the Cloudflare
# for SaaS custom-hostname lifecycle. The UNIQUE index on hostname is the
# load-bearing constraint: without it two accounts could claim the same domain
# and whoever writes KV last would win.
class CreateCustomDomains < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_domains do |t|
      t.references :account, null: false, foreign_key: true, type: :integer
      t.string :hostname, null: false
      t.boolean :canonical, null: false, default: false
      t.string :status, null: false, default: "pending"
      # Cloudflare's custom-hostname id (needed to poll status and to delete on
      # disconnect) and the DV-TXT record the author must create to validate.
      t.string :cloudflare_id
      t.string :ssl_status
      t.string :txt_name
      t.string :txt_value
      t.datetime :last_checked_at
      t.timestamps
    end

    add_index :custom_domains, :hostname, unique: true
  end
end
