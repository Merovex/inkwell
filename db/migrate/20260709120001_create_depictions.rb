class CreateDepictions < ActiveRecord::Migration[8.2]
  def change
    # Owns a book cover's ActiveStorage image, referenced by a scalar
    # depiction_id on the book version — the Body pattern, so the cover
    # versions with the book (a new cover mints a new Depiction, unchanged
    # covers carry forward by id).
    create_table :depictions do |t|
      t.timestamps
    end
  end
end
