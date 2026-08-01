# A pen name's one-line tagline — the byline's hook, shown in the author grid
# beneath the name (distinct from the longer rich-text bio). Plain column, so
# Recordable#build_successor (a dup) carries it across trash/restore versions.
class AddTaglineToAuthors < ActiveRecord::Migration[8.0]
  def change
    add_column :authors, :tagline, :string
  end
end
