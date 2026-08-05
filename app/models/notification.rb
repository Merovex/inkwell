# A person did something that concerns you — the bell's rows. Scheduled sends
# (pulse asks, drips) and operational mail are NOT notifications; your own
# actions never notify you (the caller's responsibility via `to:`).
#
# Each row carries its OWN copy — actor, sentence, door — stamped at delivery,
# so it outlives its source (accepting an invitation destroys the invitation;
# the announcement stays). Sources nullify on destruction; removing
# notifications is an explicit act on the revoke/decline path only.
class Notification < ApplicationRecord
  KINDS = %w[ invited invitation_accepted ].freeze
  # The immediate class: kinds worth an email the moment they happen. Everything
  # else is bell-only (digest-class kinds arrive with comments/replies later).
  EMAILED = %w[ invited ].freeze

  belongs_to :user   # the recipient
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :source, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc).limit(15) }

  # THE way a notification is born — never bare create!. Fan-out and channel
  # decisions live here: the row (bell) always; email per the kind's class;
  # the live dot/row via Turbo Stream to the recipient's bell.
  def self.deliver(source, to:, kind:)
    return if to.nil?

    create!(source: source, user: to, kind: kind, **copy_for(source, kind)).tap do |notification|
      NotificationMailer.public_send(kind, notification).deliver_later if EMAILED.include?(kind)
    end
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
    end
  end
  private_class_method :copy_for
end
