class User < ApplicationRecord
  include Registration
  # Attachable in rich text — @mention chips reference users by sgid.
  include ActionText::Attachable

  AVATAR_CONTENT_TYPES = %w[ image/jpeg image/png image/avif image/webp ]
  AVATAR_MAX_SIZE = 5.megabytes

  has_many :sessions, dependent: :destroy
  has_many :sign_in_codes, dependent: :destroy
  # Accounts this user belongs to; drives the post-sign-in landing (ADR 0018).
  has_many :account_users, dependent: :destroy
  has_many :accounts, through: :account_users
  # Accounts this user OWNS (superuser) — the sites the weekly digest reports on.
  # Query-only; ownership transfer/removal is a console operation (see Account).
  has_many :owned_accounts, class_name: "Account", foreign_key: :owner_id, inverse_of: :owner
  # Circles this user belongs to (the other bucket kind) — the /circles doors.
  has_many :circle_memberships, dependent: :destroy
  has_many :circles, through: :circle_memberships
  # Circle seats offered to this user (awaiting their answer), and the ones
  # they extended to others; both die with the user.
  has_many :circle_invitations, dependent: :destroy
  has_many :extended_circle_invitations, class_name: "CircleInvitation",
    foreign_key: :inviter_id, inverse_of: :inviter, dependent: :destroy
  # The rotatable invite code this user hands out (root-only until open beta),
  # and who vouched for this user at signup — the abuse-tracing referral chain.
  has_one :join_code, dependent: :destroy
  belongs_to :inviter, class_name: "User", optional: true
  # The bell's rows; plumbing, gone with the user.
  has_many :notifications, dependent: :delete_all
  # Exists so "your own boost" authorization can be a scope (BoostsController).
  has_many :boosts, foreign_key: :creator_id, inverse_of: :creator, dependent: :delete_all

  # The uploaded picture behind the avatar; absent means the monogram
  # (see ApplicationHelper#avatar_content).
  has_one_attached :avatar do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 160, 160 ]
  end

  validate :acceptable_avatar

  # :member is the baseline; :root is platform staff — the first user ever
  # (via the Setup flow), superuser across every account. Per-account authority
  # comes from ownership (accounts.owner_id), not from this global role.
  enum :role, { member: "member", root: "root" }, default: :member

  # How often this user gets the weekly site digest (the email footer's toggle):
  # weekly · fortnightly · off. Prefixed so digest_off? doesn't collide.
  enum :digest_cadence, %w[ weekly fortnightly off ].index_by(&:itself), default: "weekly", prefix: :digest

  # Everyone still receiving a digest (drops the opted-out).
  scope :digest_subscribers, -> { where.not(digest_cadence: "off") }

  # Signs the one-click cadence links in the digest footer (no login). No expiry
  # — an old digest's links keep working, like the newsletter's unsubscribe token.
  generates_token_for :digest_preferences

  # Due for this run? weekly fires each week, fortnightly every other; last_digest_at
  # both spaces the fortnightly send and guards a double-send within one run.
  def digest_due?(now: Time.current)
    return false if digest_off?
    return true if last_digest_at.nil?

    last_digest_at <= now - (digest_fortnightly? ? 13.days : 6.days)
  end

  normalizes :email_address, with: -> { it.strip.downcase }

  # Everyone's in the Commons (the town square) from their first moment —
  # invitation-free, cap-free (Circle.provision_commons seated everyone
  # earlier). Nil-safe: environments without a Commons just skip it.
  after_create_commit :join_commons

  # Uniqueness is enforced by the unique index on email_address; nothing surfaces
  # a duplicate to a user (setup can't dup, signup reuses), so no validation here.
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # The name is a handle: unique across users (case-insensitively), assigned
  # from the email at creation (see Registration#generate_handle) and editable
  # in settings. allow_blank keeps pre-handle records loadable; the create
  # callback means no new user is ever blank.
  normalizes :name, with: -> { it.strip }
  validates :name, uniqueness: { case_sensitive: false }, allow_blank: true

  # What we call the user everywhere: their handle (never blank — assigned at
  # creation), with the email as a belt-and-braces fallback for legacy rows.
  def display_name
    name.presence || email_address
  end

  # As an Action Text attachable — the @mention chip. Picking a member in the
  # Lexxy prompt attaches the user by sgid; this partial is the chip everywhere
  # (display render AND the editor round-trip, which re-renders it into the
  # attachment's content attribute).
  def to_attachable_partial_path
    "users/mention"
  end

  # What the chip reads as in plain text (excerpts, notification copy scans).
  def attachable_plain_text_representation(_caption = nil)
    "@#{display_name}"
  end

  # Keeps the stored attachment's content-type stable (Action Text would
  # otherwise stamp application/octet-stream) — mention.css keys off it.
  def attachable_content_type
    "application/vnd.actiontext.mention"
  end

  # Per-account superuser: the owner administers their account; root
  # administers every account (platform staff).
  def administers?(account)
    root? || account&.owner_id == id
  end

  # Who may hold a join code: root always; everyone once the hard-coded
  # open-beta switch flips (config.x.join_codes.open).
  def can_invite?
    root? || Rails.configuration.x.join_codes.open
  end

  # Generate a fresh single-use code and email its magic link. `purpose`
  # (:sign_in / :sign_up) tunes the email copy.
  def send_magic_link(purpose: :sign_in)
    code = sign_in_codes.create!
    SessionMailer.magic_link(self, code.plaintext, purpose:).deliver_later
  end

  private
    def join_commons
      Circle.commons&.circle_memberships&.create!(user: self)
    end

    def acceptable_avatar
      return unless avatar.attached?

      unless avatar.blob.content_type.in?(AVATAR_CONTENT_TYPES)
        errors.add(:avatar, "must be a JPG, PNG, AVIF, or WebP image")
      end
      if avatar.blob.byte_size > AVATAR_MAX_SIZE
        errors.add(:avatar, "must be smaller than #{AVATAR_MAX_SIZE / 1.megabyte} MB")
      end
    end
end
