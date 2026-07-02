class User < ApplicationRecord
  include Registration

  has_many :sessions, dependent: :destroy
  has_many :sign_in_codes, dependent: :destroy

  # :member is the baseline; :domain_admin is granted to the first user ever (via
  # the Setup flow) and administers the whole install.
  enum :role, { member: "member", domain_admin: "domain_admin" }, default: :member

  normalizes :email_address, with: -> { it.strip.downcase }

  # Uniqueness is enforced by the unique index on email_address; nothing surfaces
  # a duplicate to a user (setup can't dup, signup reuses), so no validation here.
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Generate a fresh single-use code and email its magic link. `purpose`
  # (:sign_in / :sign_up) tunes the email copy.
  def send_magic_link(purpose: :sign_in)
    code = sign_in_codes.create!
    SessionMailer.magic_link(self, code.plaintext, purpose:).deliver_later
  end
end
