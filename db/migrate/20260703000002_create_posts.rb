class CreatePosts < ActiveRecord::Migration[8.2]
  def change
    # First recordable — a blog-style post to build the spine against. Only
    # type-specific data lives here: the envelope (creator, parent, trash) is on
    # the post's Record, and the body is Action Text.
    create_table :posts do |t|
      t.string :title, null: false
      t.string :status, null: false, default: "drafted"
      t.datetime :published_at
      t.datetime :pinned_at
      t.timestamps

      t.index [ :status, :published_at ]
    end
  end
end
