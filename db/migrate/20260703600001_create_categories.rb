class CreateCategories < ActiveRecord::Migration[8.2]
  def change
    # Message-board categories, Basecamp style: an emoji icon and a name,
    # shown in the message's byline. A plain lookup table off the version
    # spine — message versions reference one by id; it never versions itself.
    create_table :categories do |t|
      t.string :name, null: false
      t.string :icon, null: false
      t.timestamps

      t.index :name, unique: true
    end
  end
end
