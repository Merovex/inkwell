class CreateAuthors < ActiveRecord::Migration[8.2]
  def change
    # A pen name / persona ON THE SPINE (a Recordable, ADR 0006/0007) — its rows
    # are versions of a Record. Always-live and edited in place (no draft/publish),
    # so only trash/restore create versions. bio is Action Text, avatar is Active
    # Storage. One version is the `default` byline, preselected when composing.
    create_table :authors do |t|
      t.string :name, null: false
      t.boolean :default, null: false, default: false
      t.integer :record_id, null: false
      t.integer :creator_id, null: false
      t.string :event, null: false, default: "created"
      t.timestamps

      t.index [ :record_id, :id ]
      t.index :record_id
      t.index :creator_id
    end

    # The chosen byline for content — keyed by the author's Record (the stable
    # id), so it survives author edits (matches Installment / Distributor).
    add_column :posts, :author_record_id, :integer
    add_column :books, :author_record_id, :integer
    add_column :series, :author_record_id, :integer
    add_index :posts, :author_record_id
    add_index :books, :author_record_id
    add_index :series, :author_record_id
  end
end
