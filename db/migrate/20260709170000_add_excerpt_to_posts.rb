class AddExcerptToPosts < ActiveRecord::Migration[8.2]
  def change
    # Author-provided summary for the blog list + meta description (SEO). Blank
    # falls back to a truncation of the body. Versioned with the post like title.
    add_column :posts, :excerpt, :text
  end
end
