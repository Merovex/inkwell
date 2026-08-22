# The public path of a record whose URL is its identity (Pages: /about/,
# /privacy/). Sparse by design — every other recordable type keeps its
# id-first Record#to_slug and leaves this NULL, so the uniqueness index is
# partial and only pages ever sit in it. Scoped to the bucket: one /about/
# per account, enforced by the database rather than by hope (versions can't
# multiply the claim, because the slug lives on the spine, not the version).
class AddSlugToRecords < ActiveRecord::Migration[8.2]
  def change
    add_column :records, :slug, :string
    add_index :records, %i[ bucket_type bucket_id slug ], unique: true,
      where: "slug IS NOT NULL", name: "index_records_on_bucket_and_slug"
  end
end
