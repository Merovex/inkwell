class AddDigestCadenceToUsers < ActiveRecord::Migration[8.2]
  def change
    # How often the weekly digest goes out to this user: weekly · fortnightly ·
    # off (the footer's "Send this fortnightly · Turn it off"). Default weekly.
    add_column :users, :digest_cadence, :string, null: false, default: "weekly"
    # When the digest last went out — guards against a double-send in a run and
    # drives the fortnightly cadence.
    add_column :users, :last_digest_at, :datetime
  end
end
