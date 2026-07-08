class CreateBodies < ActiveRecord::Migration[8.2]
  def change
    # A shareable rich-text owner. Versions reference a body by id; a new body
    # is minted only when the text actually changes, so action-only versions
    # (publish, pin, trash) share the previous one. See ADR 0007.
    create_table :bodies do |t|
      t.timestamps
    end
  end
end
