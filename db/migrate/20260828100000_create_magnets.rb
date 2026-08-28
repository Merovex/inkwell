# Reader magnets (link-not-attachment ebook delivery): a Magnet is the
# account's free ebook, a Grant is one subscriber's key to it (the claim link
# is a signed token — no token column), and a Download is one redeemed fetch
# (the audit trail that replaces a counter column). A Drop carries an optional
# magnet so the welcome email grows a claim button.
class CreateMagnets < ActiveRecord::Migration[8.2]
  def change
    create_table :magnets do |t|
      t.references :account, null: false
      t.string :title, null: false
      t.text :description
      t.timestamps
    end

    create_table :grants do |t|
      # The composite unique index below covers magnet_id lookups.
      t.references :magnet, null: false, index: false
      t.references :subscriber, null: false
      t.timestamps
      t.index [ :magnet_id, :subscriber_id ], unique: true
    end

    create_table :downloads do |t|
      t.references :grant, null: false
      t.string :format, null: false
      t.datetime :created_at, null: false
    end

    add_reference :drops, :magnet
  end
end
