# The publish pipeline's visible state (docs/phase-2-static-serving.md §2.3:
# "The admin shows build status from day one"): queued/building/live/failed +
# when the live build landed. On accounts, not the versioned Site recordable —
# build state is operational, not content.
class AddSiteBuildStatusToAccounts < ActiveRecord::Migration[8.2]
  def change
    add_column :accounts, :site_build_status, :string
    add_column :accounts, :site_built_at, :datetime
  end
end
