class CreateSeries < ActiveRecord::Migration[8.2]
  def change
    # A book series — a recordable on the spine, Publishable like Post/Message.
    # Only type-specific data lives here; the envelope (creator, trash) is on
    # the series' Record, its books are the Installment join, and the body is
    # Action Text via Body.
    create_table :series do |t|
      t.string :title, null: false
      t.string :status, null: false, default: "drafted"
      t.datetime :published_at
      t.datetime :pinned_at
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.integer :body_id, null: false
      t.string :event, null: false, default: "created"
      t.timestamps

      t.index :body_id
      t.index :creator_id
      t.index [ :record_id, :id ]
      t.index :record_id
      t.index [ :status, :published_at ]
    end
  end
end
