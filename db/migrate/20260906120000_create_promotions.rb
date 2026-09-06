# A named source of subscribers: a BookFunnel promo, a newsletter swap, or the
# permanent link on the author's own site that every promo is measured against.
#
# `ref` is the token a reader arrives carrying — today the last path segment of
# the landing page BookFunnel reports in Subscriber#source_url, which it mints
# per book-and-promo pair, so two promos featuring one book are two refs. It is
# nullable on purpose: a swap where the partner merely names you leaves nothing
# to match on, and its readers are attributed by hand or not at all. NULLs stay
# distinct under the unique index, so any number of those can coexist.
class CreatePromotions < ActiveRecord::Migration[8.2]
  def change
    create_table :promotions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :ref
      t.date :shared_on
      t.text :notes
      t.timestamps
    end

    add_index :promotions, [ :account_id, :ref ], unique: true
  end
end
