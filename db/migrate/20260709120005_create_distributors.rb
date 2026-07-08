class CreateDistributors < ActiveRecord::Migration[8.2]
  def change
    # A store buy-link for a book. Hangs off the book's Record (the stable
    # identity), not a version — links are added/removed independently of the
    # book's editorial history and carry a mutable click counter.
    create_table :distributors do |t|
      t.integer :record_id, null: false
      t.string :url, null: false
      t.string :platform, null: false
      t.integer :clicks, null: false, default: 0
      t.timestamps

      t.index :record_id
      t.index [ :record_id, :url ], unique: true
    end
  end
end
