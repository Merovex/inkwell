# Magnets get a Sluggable slug so each one has a permanent public URL — the
# direct-download delivery page (/download/<title>-<slug>). The slug column,
# not any id, anchors the link: title edits and any future re-modeling carry
# the column along, so links pasted into sent newsletters never rot.
class AddSlugToMagnets < ActiveRecord::Migration[8.2]
  def up
    add_column :magnets, :slug, :string
    Magnet.reset_column_information
    Magnet.where(slug: nil).find_each do |magnet|
      magnet.update_columns(slug: Magnet.generate_unique_slug)
    end
    change_column_null :magnets, :slug, false
    add_index :magnets, :slug, unique: true
  end

  def down
    remove_index :magnets, :slug
    remove_column :magnets, :slug
  end
end
