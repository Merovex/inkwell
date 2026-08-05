# @mentions inside circle content (messages, comments, pulse answers) — by
# handle (@benwilson) or by email (@merovex@hey.com), since people type both.
# A mention must match a CIRCLE MEMBER — it only reaches people already in the
# room, never strangers. The author can't mention themselves, and a re-scan
# never double-notifies (the existing-notification check makes it idempotent).
module Mentions
  # An email-shaped token, or a handle. Email first — greedy enough that
  # "@merovex@hey.com" captures whole instead of stopping at "merovex".
  TOKEN = /@([\w.+-]+@[\w.-]+\.\w+|[a-z0-9._]{2,})/i

  def self.deliver_for(record)
    circle = record.bucket
    return unless circle.is_a?(Circle)

    content = record.recordable.try(:content)
    tokens = content.try(:to_plain_text).to_s.scan(TOKEN).flatten.map(&:downcase).uniq
    # Members picked from the @-prompt arrive as Action Text attachments
    # (sgid → User), not as text tokens — collect those too.
    picked_ids = Array(content.try(:body).try(:attachables)).grep(User).map(&:id)

    member_ids = picked_ids.presence ? circle.members.where(id: picked_ids).pluck(:id) : []
    if tokens.any?
      member_ids |= circle.members
        .where("LOWER(users.name) IN (:tokens) OR LOWER(users.email_address) IN (:tokens)", tokens: tokens)
        .pluck(:id)
    end
    return if member_ids.empty?

    circle.members.where(id: member_ids).find_each do |member|
      next if member.id == record.creator_id
      next if Notification.exists?(source: record, user: member, kind: "mentioned")

      Notification.deliver(record, to: member, kind: "mentioned")
    end
  end
end
