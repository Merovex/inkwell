# A new comment rings the thread — the parent record's author plus everyone
# who commented earlier — wherever comments exist (circle discussions, site
# posts, the forum). The commenter never rings themselves, and anyone this
# same comment @mentioned keeps the mention (the more specific ring) instead
# of a second row. Idempotent like Mentions: an existing notification for
# this comment blocks a repeat.
module Replies
  def self.deliver_for(comment_record)
    parent = comment_record.parent
    return unless parent

    participant_ids = ([ parent.creator_id ] + parent.children.active.comments.pluck(:creator_id))
      .uniq - [ comment_record.creator_id ]
    return if participant_ids.empty?

    User.where(id: participant_ids).find_each do |user|
      next if Notification.exists?(source: comment_record, user: user, kind: %w[ mentioned replied ])

      Notification.deliver(comment_record, to: user, kind: "replied")
    end
  end
end
