class CreateBoosts < ActiveRecord::Migration[8.2]
  def change
    create_table :boosts do |t|
      t.references :record, null: false, foreign_key: true, index: false
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :content, null: false
      t.timestamps
    end
    # Serves both lookup and creation-order rendering (same shape as
    # comments/posts); no uniqueness — several boosts per person is the point.
    add_index :boosts, [ :record_id, :id ]
  end
end
