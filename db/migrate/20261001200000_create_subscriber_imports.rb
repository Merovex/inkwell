class CreateSubscriberImports < ActiveRecord::Migration[8.2]
  def change
    # A partner's sign-up export brought onto a site's list by hand
    # (SubscriberImport). The CSV itself rides Active Storage; the row is the
    # audit trail of who imported what, when, and what became of it.
    create_table :subscriber_imports do |t|
      t.references :account, null: false, foreign_key: true, type: :integer
      t.integer :creator_id, null: false
      t.string :source, null: false

      # uploaded → inviting → invited (SubscriberImport#status).
      t.string :status, null: false, default: "uploaded"
      # Outcome => count, stamped when the invitations go out.
      t.json :tally
      t.datetime :invited_at

      t.timestamps
    end
    add_index :subscriber_imports, :creator_id
  end
end
