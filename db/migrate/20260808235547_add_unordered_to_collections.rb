class AddUnorderedToCollections < ActiveRecord::Migration[8.2]
  def change
    add_column :collections, :unordered, :boolean, default: false, null: false
  end
end
