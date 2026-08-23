# The cross-site suppression projection (ADR 0027): append-only rows keyed on
# Person — imposed by hard bounces and complaints, lifted by reconfirmation or
# an admin's say-so (a lift is a row pointing at the row it lifts; nothing is
# ever updated or deleted). scope nil means every site; an Account scope means
# that site only. Built here from the ledgers (Suppression.rebuild!) and
# rebuildable from them any time the projection is doubted.
class CreateSuppressions < ActiveRecord::Migration[8.2]
  def change
    create_table :suppressions do |t|
      t.references :person, null: false, index: false
      t.string :reason, null: false
      t.references :scope, polymorphic: true, null: true, index: false
      t.references :lifted, null: true, index: true
      t.datetime :created_at, null: false
      t.index [ :person_id, :scope_type, :scope_id, :created_at ], name: "index_suppressions_on_person_scope_time"
    end

    reversible do |direction|
      direction.up { Suppression.rebuild! }
    end
  end
end
