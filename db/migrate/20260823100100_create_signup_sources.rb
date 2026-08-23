# The identity-free residue of every consent event (SignupSource, ADR 0026):
# site + source fingerprint + action + time, nothing that names a reader. No
# foreign key to subscribers on purpose — the row exists to survive the
# subscriber's purge. Backfilled from the consent log's fingerprints (written
# by the previous migration) so the residue starts as complete as the log.
class CreateSignupSources < ActiveRecord::Migration[8.2]
  def change
    create_table :signup_sources do |t|
      t.references :account, null: false
      t.string :source_fingerprint, null: false
      t.string :action, null: false
      t.datetime :created_at, null: false
      t.index [ :source_fingerprint, :created_at ]
    end

    reversible do |direction|
      direction.up do
        SubscriptionEvent.where.not(source_fingerprint: nil).includes(:subscriber).find_each do |event|
          SignupSource.trace(event)
        end
      end
    end
  end
end
