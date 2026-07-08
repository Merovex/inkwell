class CreateChatLines < ActiveRecord::Migration[8.2]
  def change
    create_table :chat_lines do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, default: "created", null: false
      t.timestamps
    end

    add_index :chat_lines, [ :record_id, :id ]
    add_index :chat_lines, :creator_id
  end
end
