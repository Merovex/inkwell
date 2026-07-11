class CreateMissives < ActiveRecord::Migration[8.2]
  def change
    # A contact-form submission — standalone (like Subscriber), NOT on the
    # Record/Recordable spine. Double opt-in is the reputation guard: a row is
    # unconfirmed until the submitter clicks the emailed confirmation link, so the
    # form can't be used to send our domain's mail to a victim address. The name,
    # subject, and body are only ever read by an admin in /admin/missives — they
    # are never emitted in any outbound mail. Lifecycle is derived from timestamps
    # (see Missive scopes): visible 30 days, trashed to 60, then purged.
    create_table :missives do |t|
      t.string :name, null: false
      t.string :email_address, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.datetime :confirmed_at
      t.string :consent_ip
      t.timestamps

      t.index :created_at
      t.index :confirmed_at
    end
  end
end
