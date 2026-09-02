# Platform announcements (the Basecamp bulletin): root staff to every user.
# A Publishable recordable — same version-table shape as messages, no
# category. The record rows carry a NIL bucket (see AllowPlatformRecords).
class CreateBulletins < ActiveRecord::Migration[8.1]
  def change
    create_table :bulletins do |t|
      t.string :title, null: false
      t.string :status, default: "drafted", null: false
      t.datetime :published_at
      t.datetime :pinned_at
      t.integer :record_id
      t.integer :creator_id, null: false
      t.integer :body_id, null: false
      t.string :event, default: "created", null: false
      t.timestamps
      t.index :record_id
    end
  end
end
