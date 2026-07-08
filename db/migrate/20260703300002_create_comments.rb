class CreateComments < ActiveRecord::Migration[8.2]
  def change
    create_table :comments do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, default: "created", null: false
      t.timestamps
    end

    add_index :comments, [ :record_id, :id ]
    add_index :comments, :creator_id
  end
end
