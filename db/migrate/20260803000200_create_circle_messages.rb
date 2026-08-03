# A message on a circle's board — a recordable on the spine, like ChatLine and
# Comment: public the instant it's saved (no draft regime), every edit a tracked
# version. Rich text lives on the version directly (Action Text). Unlike a chat
# line it carries a title, because a board reads as titled threads.
class CreateCircleMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :circle_messages do |t|
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string  :event, null: false, default: "created"
      t.string  :title
      t.timestamps
    end
    add_index :circle_messages, [ :record_id, :id ]
    add_index :circle_messages, :creator_id
  end
end
