class CreateStreams < ActiveRecord::Migration[8.2]
  def change
    # One subscriber's run through a Drip ("enrollment"). enrolled_at (the
    # subscriber's confirmed_at) anchors every Drop's send time. Unique per
    # (subscriber, drip) so a confirm can't double-enroll. drip_record_id points
    # at the Drip's stable Record, surviving edits to the campaign.
    create_table :streams do |t|
      t.references :subscriber, null: false, foreign_key: true
      t.references :drip_record, null: false, foreign_key: { to_table: :records }
      t.datetime :enrolled_at, null: false
      t.datetime :ended_at
      t.string   :ended_reason
      t.timestamps

      t.index [ :subscriber_id, :drip_record_id ], unique: true
    end
  end
end
