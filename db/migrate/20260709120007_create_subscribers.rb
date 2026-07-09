class CreateSubscribers < ActiveRecord::Migration[8.2]
  def change
    # Newsletter subscribers — anonymous mailing-list opt-ins, distinct from
    # authenticated users. This row is the *current-state projection* (one per
    # email, deduped by the unique index); the immutable consent history lives
    # in subscription_events. See ADR 0011.
    create_table :subscribers do |t|
      t.string :email_address, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :confirmed_at
      t.datetime :unsubscribed_at
      t.string :source        # where they signed up (nav, hero, book page…)
      t.string :consent_ip    # the IP at opt-in — consent evidence
      t.timestamps

      t.index :email_address, unique: true
    end
  end
end
