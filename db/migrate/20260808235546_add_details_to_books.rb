class AddDetailsToBooks < ActiveRecord::Migration[8.2]
  def change
    add_column :books, :word_count, :integer
    add_column :books, :isbn, :string
    add_column :books, :tagline, :string
  end
end
