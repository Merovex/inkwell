class CreateBooks < ActiveRecord::Migration[8.2]
  def change
    # A book — a recordable on the spine, Publishable like Post/Message, plus
    # a real-world publication_date (distinct from published_at, which is when
    # this record went live) and a versioned cover via depiction_id. Series
    # membership + order live on the Installment join, not here.
    create_table :books do |t|
      t.string :title, null: false
      t.string :status, null: false, default: "drafted"
      t.datetime :published_at
      t.datetime :pinned_at
      t.date :publication_date
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.integer :body_id, null: false
      t.integer :depiction_id
      t.string :event, null: false, default: "created"
      t.timestamps

      t.index :body_id
      t.index :creator_id
      t.index :depiction_id
      t.index [ :record_id, :id ]
      t.index :record_id
      t.index [ :status, :published_at ]
    end
  end
end
