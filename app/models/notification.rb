# Something happened that concerns you — the bell's rows. Mostly a person's
# act (invitations, mentions, boosts); the one scheduled exception is the
# pulse ask, which rings the bell alongside its own mailer. Operational mail
# (drips, digests) stays out, and your own actions never notify you (the
# caller's responsibility via `to:`).
#
# Each row carries its OWN copy — actor, sentence, door — stamped at delivery,
# so it outlives its source (accepting an invitation destroys the invitation;
# the announcement stays). Sources nullify on destruction; removing
# notifications is an explicit act on the revoke/decline path only.
class Notification < ApplicationRecord
  KINDS = %w[ invited invitation_accepted mentioned boosted pulse_asked replied ].freeze
  # Email-worthy kinds. Nothing notification-shaped is time-sensitive: these
  # roll up into digest emails (NotificationDigestJob) — and reading in-app
  # first cancels the email (the bell beat us to it). The rest (acceptances,
  # boosts) are bell-only. pulse_asked is bell-only HERE because its email is
  # PulseMailer's immediate ask — the question shouldn't arrive twice.
  EMAILED = %w[ invited mentioned replied ].freeze
  # Replies ride the once-a-day digest, not the 4-hour one — thread chatter
  # shouldn't bug anyone. (Bell rings live regardless.)
  EMAILED_DAILY = %w[ replied ].freeze

  belongs_to :user   # the recipient
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :source, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc).limit(15) }

  # THE way a notification is born — never bare create!. Fan-out and channel
  # decisions live here: the row (bell) always, live via Turbo Stream; email
  # waits for the 4-hour digest (EMAILED kinds only).
  def self.deliver(source, to:, kind:)
    return if to.nil?

    create!(source: source, user: to, kind: kind, **copy_for(source, kind))
  end

  # Live bell: prepend the row and light the dot in the recipient's header.
  after_create_commit do
    broadcast_prepend_later_to [ user, :notifications ], target: "notifications-list",
      partial: "notifications/notification", locals: { notification: self }
    broadcast_replace_later_to [ user, :notifications ], target: "notification-indicator",
      partial: "notifications/indicator", locals: { unread: true }
  end

  # The row's stamped copy, per kind — computed once, at delivery.
  def self.copy_for(source, kind)
    case kind
    when "invited"
      { actor: source.inviter, url: "/circles",
        title: "#{source.inviter.display_name} invited you to #{source.circle.name}" }
    when "invitation_accepted"
      { actor: source.user, url: "/circles/#{source.circle.slug}/members",
        title: "#{source.user.display_name} accepted your invitation to #{source.circle.name}" }
    when "mentioned" # source: the Record the mention appears in
      { actor: source.creator, url: record_path_for(source),
        title: "#{source.creator.display_name} mentioned you in #{context_for(source)}" }
    when "boosted"   # source: the Boost
      { actor: source.creator, url: record_path_for(source.record),
        title: "#{source.creator.display_name} boosted your #{noun_for(source.record)}: #{source.content}" }
    when "pulse_asked" # source: the Pulse's Record — the schedule fired, no human actor
      { actor: nil, url: record_path_for(source),
        title: "Pulse check in #{source.bucket.name}: #{source.recordable.question}" }
    when "replied" # source: the new comment's Record — rings the thread (Replies)
      { actor: source.creator, url: record_path_for(source),
        title: "#{source.creator.display_name} commented on #{thread_for(source.parent)}" }
    end
  end
  private_class_method :copy_for

  # Record page paths, stamped as strings. Circle content for most kinds;
  # replied also arises from site-side comments (posts, forum), whose admin
  # lives at a script_name mount on the same app host (Account#admin_path).
  def self.record_path_for(record)
    if record.bucket_type == "Account"
      admin = record.bucket.admin_path
      case record.recordable_type
      when "Post"    then "#{admin}/posts/#{record.id}"
      when "Message" then "#{admin}/forum/#{record.id}"
      when "Comment" then "#{record_path_for(record.parent)}#comment_#{record.id}"
      else admin
      end
    else
      slug = record.bucket.slug
      case record.recordable_type
      when "Message" then "/circles/#{slug}/messages/#{record.id}"
      when "Comment" then "#{record_path_for(record.parent)}#comment_#{record.id}"
      when "Beat"    then "/circles/#{slug}/pulses/#{record.parent_id}"
      when "Pulse"   then "/circles/#{slug}/pulses/#{record.id}"
      else "/circles/#{slug}"
      end
    end
  end
  private_class_method :record_path_for

  # What a comment thread hangs from, for replied copy: the parent's title
  # (message, post) or question (pulse), else a noun.
  def self.thread_for(parent)
    title = parent.recordable.try(:title) || parent.recordable.try(:question)
    title ? "“#{title}”" : (parent.recordable_type == "Beat" ? "a Pulse answer" : "a post")
  end
  private_class_method :thread_for

  def self.context_for(record)
    case record.recordable_type
    when "Message" then "“#{record.recordable.title}”"
    when "Comment" then "a comment on “#{record.parent.recordable.try(:title) || record.parent.recordable.try(:question)}”"
    when "Beat"    then "a Pulse answer"
    else record.bucket.name
    end
  end
  private_class_method :context_for

  def self.noun_for(record)
    { "Message" => "message", "Comment" => "comment", "Beat" => "answer" }.fetch(record.recordable_type, "post")
  end
  private_class_method :noun_for
end
