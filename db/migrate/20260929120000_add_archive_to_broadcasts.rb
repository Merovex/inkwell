# Every broadcast gets a permanent browser-view archive (/newsletters/<title>-<slug>):
# a Sluggable slug to anchor the link, plus the issue frozen as it went out —
# title and rendered HTML, tip-in included — stamped when the fan-out starts.
# Broadcasts sent before this existed were never frozen; their archive is a
# best-effort freeze of the post's current version (close, not guaranteed).
class AddArchiveToBroadcasts < ActiveRecord::Migration[8.2]
  def up
    add_column :broadcasts, :slug, :string
    add_column :broadcasts, :issue_title, :string
    add_column :broadcasts, :issue_html, :text
    add_column :broadcasts, :issued_at, :datetime

    Broadcast.reset_column_information
    Broadcast.where(slug: nil).find_each do |broadcast|
      broadcast.update_columns(slug: Broadcast.generate_unique_slug)
    end
    change_column_null :broadcasts, :slug, false
    add_index :broadcasts, :slug, unique: true

    Broadcast.where.not(sent_at: nil).find_each do |broadcast|
      broadcast.issue!(at: broadcast.sent_at) if broadcast.post
    end
  end

  def down
    remove_index :broadcasts, :slug
    remove_column :broadcasts, :issued_at
    remove_column :broadcasts, :issue_html
    remove_column :broadcasts, :issue_title
    remove_column :broadcasts, :slug
  end
end
