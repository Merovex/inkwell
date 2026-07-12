# A newsletter subscriber — an anonymous mailing-list opt-in, deliberately
# separate from User (no session, no role, no login). This row holds the
# *current* state (one per email, deduped by the unique index); the immutable
# consent history lives in SubscriptionEvent. Double opt-in is the consent
# proof: a new opt-in is always :pending until the emailed confirmation link
# flips it (SubscriberMailer#confirmation). See ADR 0011.
class Subscriber < ApplicationRecord
  has_many :events, -> { order(:created_at) }, class_name: "SubscriptionEvent", dependent: :destroy
  has_many :broadcast_deliveries, dependent: :destroy

  enum :status, %w[ pending confirmed unsubscribed ].index_by(&:itself), default: "pending"

  # Engagement-based sunset thresholds (ADR 0014). "Engagement" is any open or
  # click; any of them resets the clock. Ask ("still want these?") at the later
  # of DAYS/EMAILS since last engagement, but no later than the ask cap; then, if
  # still silent through the grace window, drop — never past the hard cap.
  RE_ENGAGE_DAYS    = 90
  RE_ENGAGE_EMAILS  = 6
  RE_ENGAGE_CAP_DAYS = 275
  GRACE_DAYS   = 90
  GRACE_EMAILS = 3
  HARD_CAP_DAYS = 365

  normalizes :email_address, with: -> { it.strip.downcase }

  validates :email_address, presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true

  # The confirmation-link token expires but is otherwise stable — it does NOT
  # fold in confirmed_at. Email clients and security scanners routinely GET a
  # link once before the human clicks; if the token were invalidated on first
  # use, that prefetch would confirm the subscriber and leave the human's click
  # with a dead 404. Keeping it resolvable lets the confirm action recognize an
  # already-confirmed subscriber and say so (confirm! is idempotent). The
  # unsubscribe token is stable and never expires — one-click opt-out in every email.
  generates_token_for :confirmation, expires_in: 7.days
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

  # ── Engagement-based sunset ────────────────────────────────────────────────

  # The sunset job only acts once open/click tracking is live (SES) — before
  # then everyone looks cold, and we must not drop a whole list on absent data.
  def self.sunset_enabled?
    Rails.configuration.x.newsletter.sunset_enabled
  end

  # An open or click resets the engagement clock; a pending nudge is cleared, so
  # they're fully back in the fold.
  def mark_engaged!
    update!(last_engaged_at: Time.current, re_engagement_sent_at: nil)
  end

  # What the weekly job should do with this subscriber right now (or nil).
  def sunset_action
    return unless confirmed?
    return unless days_since_engagement  # never emailed → nothing to judge

    if re_engagement_sent_at
      :drop if dropworthy?
    elsif nudgeworthy?
      :re_engage
    end
  end

  # Send the one-time "still want these?" nudge and start the grace clock.
  def send_re_engagement
    update!(re_engagement_sent_at: Time.current)
    SubscriberMailer.re_engagement(self, generate_token_for(:unsubscribe)).deliver_later
  end

  # Days since the last open/click, anchored to first contact if never engaged.
  # Memoized — the sweep asks several times per subscriber.
  def days_since_engagement
    return @days_since_engagement if defined?(@days_since_engagement)

    anchor = last_engaged_at || broadcast_deliveries.minimum(:sent_at)
    @days_since_engagement = anchor && ((Time.current - anchor) / 1.day).floor
  end

  # Emails sent since the last engagement (all of them if never engaged).
  def emails_since_engagement
    scope = last_engaged_at ? broadcast_deliveries.where("sent_at > ?", last_engaged_at) : broadcast_deliveries
    scope.count
  end

  private
    def nudgeworthy?
      (days_since_engagement >= RE_ENGAGE_DAYS && emails_since_engagement >= RE_ENGAGE_EMAILS) ||
        days_since_engagement >= RE_ENGAGE_CAP_DAYS
    end

    def dropworthy?
      grace_days = ((Time.current - re_engagement_sent_at) / 1.day).floor
      grace_emails = broadcast_deliveries.where("sent_at > ?", re_engagement_sent_at).count

      days_since_engagement >= HARD_CAP_DAYS || (grace_days >= GRACE_DAYS && grace_emails >= GRACE_EMAILS)
    end
end
