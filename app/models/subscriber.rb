# A newsletter subscriber — an anonymous mailing-list opt-in, deliberately
# separate from User (no session, no role, no login). This row holds the
# *current* state (one per email, deduped by the unique index); the immutable
# consent history lives in SubscriptionEvent. Double opt-in is the consent
# proof: a new opt-in is always :pending until the emailed confirmation link
# flips it (SubscriberMailer#confirmation). See ADR 0011.
class Subscriber < ApplicationRecord
  has_many :events, -> { order(:created_at) }, class_name: "SubscriptionEvent", dependent: :destroy

  enum :status, %w[ pending confirmed unsubscribed ].index_by(&:itself), default: "pending"

  normalizes :email_address, with: -> { it.strip.downcase }

  validates :email_address, presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true

  # The confirmation-link token expires and folds in confirmed_at, so a link
  # can't reconfirm once used. The unsubscribe token is stable and never
  # expires — it rides in every email for one-click opt-out.
  generates_token_for :confirmation, expires_in: 7.days do
    confirmed_at
  end
  generates_token_for :unsubscribe

  # A public opt-in: create or revive the row (deduped by email) and append the
  # matching consent event. New or previously-unsubscribed consent always lands
  # as :pending — double opt-in confirms it. Idempotent for an already-confirmed
  # address (no state change, no event). Any pending result gets a fresh
  # confirmation email. Returns the subscriber.
  def self.opt_in(email_address:, source: nil, ip: nil)
    subscriber = transaction do
      record = find_or_initialize_by(email_address: normalize_value_for(:email_address, email_address))

      action =
        if record.confirmed?      then nil
        elsif record.persisted? && record.unsubscribed? then "resubscribed"
        else "subscribed"
        end

      record.source = source if source
      record.consent_ip = ip if ip
      record.status = :pending unless record.confirmed?
      record.save!
      record.log_event!(action, ip:, source:) if action
      record
    end

    subscriber.send_confirmation if subscriber.pending?
    subscriber
  end

  # Email the tokened confirmation link (double opt-in). Enqueued, so it fires
  # after the opt-in transaction commits.
  def send_confirmation
    SubscriberMailer.confirmation(self, generate_token_for(:confirmation)).deliver_later
  end

  # Complete double opt-in: the confirmation link was clicked.
  def confirm!(ip: nil)
    return if confirmed?

    transaction do
      update!(status: :confirmed, confirmed_at: Time.current)
      log_event!("confirmed", ip:)
    end
  end

  # Honor an opt-out. The row is kept (never deleted) as a suppression record.
  def unsubscribe!(ip: nil, source: nil)
    return if unsubscribed?

    transaction do
      update!(status: :unsubscribed, unsubscribed_at: Time.current)
      log_event!("unsubscribed", ip:, source:)
    end
  end

  # Append one immutable event to the consent log.
  def log_event!(action, ip: nil, source: nil)
    events.create!(action: action, ip_address: ip, source: source)
  end
end
