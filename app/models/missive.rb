# A contact-form submission. Deliberately standalone (like Subscriber): no User,
# no session, not on the Record spine. Double opt-in is the reputation guard —
# a submission is unconfirmed until the emailed confirmation link is clicked, so
# the form can't make our mail server send attacker-supplied text to a victim's
# inbox. The submitter's name/subject/body are read ONLY in /admin/missives and
# never appear in any outbound email (the confirmation is a fixed template; the
# daily digest is a count). Replies go out from the admin's own mail client via
# a mailto: link — never through this app.
#
# Lifecycle is derived from timestamps, not a status column:
#   - unconfirmed (confirmed_at nil): never shown; purged after UNCONFIRMED_TTL.
#   - active   (confirmed, ≤ VISIBLE_DAYS old): the admin feed.
#   - trashed  (confirmed, VISIBLE_DAYS–TRASH_DAYS old): the admin Trash tab.
#   - purged   (older than TRASH_DAYS, or unconfirmed past its TTL): hard-deleted.
class Missive < ApplicationRecord
  VISIBLE_DAYS   = 30   # shown in the main feed
  TRASH_DAYS     = 60   # then hidden in Trash until this age, then purged
  UNCONFIRMED_TTL = 7.days # never-confirmed submissions swept after this

  normalizes :email_address, with: -> { it.strip.downcase }

  validates :name, :subject, presence: true
  validates :body, presence: true, length: { maximum: 5_000 }
  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Stateless signed confirmation token, valid for 3 days. It is NOT folded on
  # confirmed_at: email clients/scanners often GET the link once before the human
  # clicks, and invalidating on first use would leave the human's click on a dead
  # 404. Keeping it resolvable lets the confirm action recognize an already-confirmed
  # missive and say so (confirm! is idempotent). (Unconfirmed rows outlive the
  # token by a few days before the purge sweep clears them.)
  generates_token_for :confirmation, expires_in: 3.days

  scope :confirmed,   -> { where.not(confirmed_at: nil) }
  scope :unconfirmed, -> { where(confirmed_at: nil) }
  # The admin feed (reverse-chron) and its Trash tab, keyed off submission age.
  scope :active,  -> { confirmed.where(created_at: VISIBLE_DAYS.days.ago..).order(created_at: :desc) }
  scope :trashed, -> { confirmed.where(created_at: TRASH_DAYS.days.ago...VISIBLE_DAYS.days.ago).order(created_at: :desc) }
  # Everything the purge sweep should delete: confirmed past the trash window, or
  # never-confirmed and past its short TTL.
  scope :purgeable, lambda {
    where(created_at: ...TRASH_DAYS.days.ago)
      .or(unconfirmed.where(created_at: ...UNCONFIRMED_TTL.ago))
  }

  # A public contact submission: persist as unconfirmed and email the tokened
  # confirmation link. Each submission is its own row (no dedup — a person may
  # write more than once). Returns the missive.
  def self.submit(name:, email_address:, subject:, body:, ip: nil)
    missive = create!(name: name, email_address: email_address, subject: subject, body: body, consent_ip: ip)
    missive.send_confirmation
    missive
  end

  # Email the fixed-template confirmation link (double opt-in). Enqueued so it
  # fires after the create commits. Carries NO submitter-entered content.
  def send_confirmation
    MissiveMailer.confirmation(self, generate_token_for(:confirmation)).deliver_later
  end

  # Complete double opt-in: the confirmation link was clicked. Idempotent.
  def confirm!
    return if confirmed?

    update!(confirmed_at: Time.current)
  end

  def confirmed?
    confirmed_at.present?
  end
end
