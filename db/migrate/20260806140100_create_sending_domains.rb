# BYOD sending domains (docs/email-tenant-byod-plan.md) — the email twin of
# custom_domains: one row per connected SES identity (e.g. news.merovex.press),
# carrying the DKIM CNAMEs and MAIL FROM domain the author must publish.
class CreateSendingDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :sending_domains do |t|
      t.belongs_to :account, null: false, foreign_key: true
      t.string :domain, null: false
      t.string :status, null: false, default: "pending"
      t.json :dkim_tokens
      t.string :mail_from_domain
      t.datetime :last_checked_at
      t.timestamps
    end
    add_index :sending_domains, :domain, unique: true
  end
end
