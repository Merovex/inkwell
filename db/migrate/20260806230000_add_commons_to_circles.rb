# The Commons: ONE platform-wide circle every user belongs to (the town
# square — the Wall's first home; Bulletins affix to it). The partial unique
# index makes the singleton a database fact.
class AddCommonsToCircles < ActiveRecord::Migration[8.1]
  def change
    add_column :circles, :commons, :boolean, default: false, null: false
    add_index :circles, :commons, unique: true, where: "commons"
  end
end
