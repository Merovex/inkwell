class CreateAccounts < ActiveRecord::Migration[8.2]
  def up
    create_table :accounts do |t|
      t.string     :name, null: false
      t.string     :slug, null: false, index: { unique: true }
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string     :domain, index: { unique: true }
      t.string     :contact_email
      t.timestamps
    end

    seed_first_account
  end

  def down
    drop_table :accounts
  end

  private
    # An existing install becomes account 1 (the Merovex Press cut-in),
    # carrying contact_email over from the settings singleton (retired in 1.5).
    # A fresh database has no users yet and skips this; its first account
    # arrives through setup, not a migration.
    def seed_first_account
      owner_id = select_value("SELECT id FROM users ORDER BY id LIMIT 1") or return
      name  = select_value("SELECT site_name FROM settings LIMIT 1").presence || "Merovex Press"
      email = connection.quote(select_value("SELECT contact_email FROM settings LIMIT 1"))

      execute <<~SQL
        INSERT INTO accounts (name, slug, owner_id, domain, contact_email, created_at, updated_at)
        VALUES (#{connection.quote(name)}, #{connection.quote(generate_slug)}, #{owner_id},
                'merovex.press', #{email}, datetime('now'), datetime('now'))
      SQL
    end

    # Sluggable's format, inlined so the migration never depends on app code.
    def generate_slug
      letters = "ABCDEFGHJKMNPQRSTVWXYZ"
      crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
      letters.chars.sample(random: SecureRandom) +
        SecureRandom.alphanumeric(5, chars: crockford.chars)
    end
end
