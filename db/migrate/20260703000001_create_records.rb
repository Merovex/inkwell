class CreateRecords < ActiveRecord::Migration[8.2]
  def change
    create_table :records do |t|
      t.string :recordable_type, null: false
      t.bigint :recordable_id, null: false
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.references :parent, foreign_key: { to_table: :records }
      t.integer :position
      t.datetime :trashed_at
      t.timestamps

      t.index [ :recordable_type, :recordable_id ], unique: true
    end
  end
end
