class CreateInstallments < ActiveRecord::Migration[8.2]
  def change
    # A book's placement in a series. Joins two Records (the stable identities,
    # not version rows) so memberships survive versioning; a book can appear in
    # many series, and position orders the books within a given series.
    create_table :installments do |t|
      t.integer :series_record_id, null: false
      t.integer :book_record_id, null: false
      t.integer :position
      t.timestamps

      t.index [ :series_record_id, :book_record_id ], unique: true
      t.index [ :series_record_id, :position ]
      t.index :book_record_id
    end
  end
end
