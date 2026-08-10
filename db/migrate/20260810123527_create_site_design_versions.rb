# The public site's design becomes a versioned record instead of a single
# serialized blob on accounts. Each account carries exactly one `drafted`
# working version (what the SiteDesigner edits and the preview host serves)
# and one `published` live version (what production builds from); older
# published designs settle to `archived` as history/rollback points. The
# old accounts.design column folds into these rows.
class CreateSiteDesignVersions < ActiveRecord::Migration[8.2]
  def up
    create_table :site_design_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.json :data, null: false, default: {}
      t.string :status, null: false, default: "drafted"
      t.string :label
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime :published_at
      t.timestamps
    end

    # At most one drafted and one published per account; archived rows are
    # unbounded history.
    add_index :site_design_versions, :account_id, unique: true,
      where: "status = 'drafted'", name: "index_site_design_versions_one_draft"
    add_index :site_design_versions, :account_id, unique: true,
      where: "status = 'published'", name: "index_site_design_versions_one_published"

    # Fold each account's serialized design into a live version plus a working
    # copy, so production has something to build and the designer has a draft
    # to edit the moment this ships.
    say_with_time "backfilling site_design_versions from accounts.design" do
      now = quote(Time.current)
      select_all("SELECT id, design FROM accounts").each do |row|
        data = quote(row["design"].presence || "{}") # design is stored as a JSON string
        execute <<~SQL.squish
          INSERT INTO site_design_versions
            (account_id, data, status, published_at, created_at, updated_at)
          VALUES (#{row["id"].to_i}, #{data}, 'published', #{now}, #{now}, #{now})
        SQL
        execute <<~SQL.squish
          INSERT INTO site_design_versions
            (account_id, data, status, created_at, updated_at)
          VALUES (#{row["id"].to_i}, #{data}, 'drafted', #{now}, #{now})
        SQL
      end
    end

    remove_column :accounts, :design
  end

  def down
    add_column :accounts, :design, :text
    execute <<~SQL.squish
      UPDATE accounts SET design = (
        SELECT data FROM site_design_versions
        WHERE site_design_versions.account_id = accounts.id
          AND site_design_versions.status = 'published'
        LIMIT 1
      )
    SQL
    drop_table :site_design_versions
  end
end
