class User < ApplicationRecord
  include Registration

  AVATAR_CONTENT_TYPES = %w[ image/jpeg image/png image/avif image/webp ]
  AVATAR_MAX_SIZE = 5.megabytes

  has_many :sessions, dependent: :destroy
  has_many :sign_in_codes, dependent: :destroy
  # Accounts this user belongs to; drives the post-sign-in landing (ADR 0018).
  has_many :account_users, dependent: :destroy
  has_many :accounts, through: :account_users
  # Circles this user belongs to (the other bucket kind) — the /circles doors.
  has_many :circle_memberships, dependent: :destroy
  has_many :circles, through: :circle_memberships
  # The rotatable invite code this user hands out (root-only until open beta),
  # and who vouched for this user at signup — the abuse-tracing referral chain.
  has_one :join_code, dependent: :destroy
  belongs_to :inviter, class_name: "User", optional: true
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

  normalizes :email_address, with: -> { it.strip.downcase }

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
