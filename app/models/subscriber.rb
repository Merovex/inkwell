# A newsletter subscriber — an anonymous mailing-list opt-in, deliberately
# separate from User (no session, no role, no login). This row holds the
# *current* state (one per email, deduped by the unique index); the immutable
# consent history lives in SubscriptionEvent. Double opt-in is the consent
# proof: a new opt-in is always :pending until the emailed confirmation link
# flips it (SubscriberMailer#confirmation). See ADR 0011.
class Subscriber < ApplicationRecord
  # The press this reader subscribed to, and the person behind the address
  # (1.6): one Person per email globally, one Subscriber per person per press.
  belongs_to :account, default: -> { Current.account }
  belongs_to :person

  # A subscriber built from a bare email self-provisions its Person, so every
  # creation path (opt-in, imports, tests) stays one call.
  before_validation :assign_person

  has_many :events, -> { order(:created_at) }, class_name: "SubscriptionEvent", dependent: :destroy
  has_many :broadcast_deliveries, dependent: :destroy
  has_many :streams, dependent: :destroy
  has_many :delivery_events, dependent: :delete_all

  enum :status, %w[ pending confirmed unsubscribed bounced complained ].index_by(&:itself), default: "pending"

  # Deliverability-seed inboxes (diagnostic services, not people). A seed may
  # subscribe and confirm — the confirmation email is what those services
  # analyze — but gets nothing further: no broadcasts, no drips (an expired
  # seed inbox hard-bounces, and bounces are reputation damage). Seeds are
  # also excluded from roster counts. Matched by domain or subdomain at
  # creation; rotating-domain services (GlockApps, Everest) are flagged
  # manually from the admin roster.
  SEED_DOMAINS = %w[
    aboutmy.email
    mail-tester.com
    mailosaur.net
    mailosaur.io
    mailtrap.io
    ethereal.email
    mailslurp.com
    mailslurp.net
    testmail.app
    emailonacid.com
    litmusemail.com
    litmus.com
  ].freeze

  # Reserved TLDs (RFC 2606/6761) can never receive mail; reject them
  # deterministically rather than leaning on a DNS lookup.
  RESERVED_TLDS = %w[ test invalid localhost example ].freeze

  # The pinned honeypot field on public signup forms — one fixed name shared
  # by the controller and the export contract (Exporter#newsletter_block), so
  # the static form and the server can never drift. Session-backed traps
  # can't work on a form baked at build time; a fixed decoy field can. Named
  # to look like a real profile field so bots fill it.
  HONEYPOT_FIELD = "website"

  # The people, as opposed to the diagnostics: everyone who isn't a seed.
  # Roster counts count readers.
  scope :readers, -> { where(seed: false) }
  # Who actually gets broadcasts and drips: confirmed, and not a seed.
  scope :sendable, -> { confirmed.readers }

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
    uniqueness: { scope: :account_id }

  # Email hygiene, on: :create only — a domain that later lands on a blocklist
  # must never wedge unsubscribe!/mark_bounced! (both update! the row), and the
  # address is immutable after creation anyway. One ladder serves both this
  # gate and the rejection log: see .rejection_reason. No MX lookup — double
  # opt-in IS the MX check (an undeliverable domain never confirms, and the
  # signup POST shouldn't stall on DNS); pure list checks only, so no network
  # in any environment. The disposable check's allow-list carveout is how
  # SEED_DOMAINS stay subscribable even when the gem's list contains them (it
  # does: mail-tester, mailosaur, …); see the valid_email2 initializer.
  validate :email_address_deliverable, on: :create

  before_create :flag_seed_domain

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
      person = Person.find_or_create_by!(email_address: normalize_value_for(:email_address, email_address))
      record = Current.account.subscribers.find_or_initialize_by(person: person)
      record.email_address = person.email_address

      action =
        if record.confirmed?      then nil
        elsif record.persisted? && (record.unsubscribed? || record.bounced? || record.complained?) then "resubscribed"
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

  # Complete double opt-in: the confirmation link was clicked. Confirmation is
  # the drip trigger — enroll into every active Drip, then advance each stream so
  # any day-0 Drop goes out right away (later Drops fire via the daily tick).
  def confirm!(ip: nil)
    return if confirmed?

    transaction do
      update!(status: :confirmed, confirmed_at: Time.current)
      log_event!("confirmed", ip:)
    end

    # Seeds stop here: the confirmation email is the whole test. No drips.
    return if seed?

    Drip.enroll(self)
    streams.active.find_each { |stream| DripAdvanceJob.perform_later(stream) }
  end

  # Honor an opt-out. The row is kept (never deleted) as a suppression record.
  # Any in-flight drip runs end here so no further Drops go out (the tick's own
  # confirmed? guard is a backstop). A complaint already suppresses harder than
  # an opt-out — never downgrade it to a mere unsubscribe.
  def unsubscribe!(ip: nil, source: nil)
    return if unsubscribed? || complained?

    transaction do
      update!(status: :unsubscribed, unsubscribed_at: Time.current)
      log_event!("unsubscribed", ip:, source:)
    end

    streams.active.find_each { |stream| stream.end!("unsubscribed") }
  end

  # A permanent delivery failure (hard bounce): suppress like an unsubscribe —
  # the row is kept, no more sends — but as its own status so the roster can
  # tell "address is dead" from "asked to leave". An explicit opt-out or a
  # complaint outranks it (never downgrade either). A later opt-in revives the
  # row through the normal pending → double-opt-in path, which proves the
  # mailbox works again.
  def mark_bounced!(source: nil)
    return if bounced? || unsubscribed? || complained?

    transaction do
      update!(status: :bounced)
      log_event!("bounced", source:)
    end

    streams.active.find_each { |stream| stream.end!("bounced") }
  end

  # Lift a delivery suppression (the admin's "Reactivate"). Two shapes, by
  # what the suppression meant:
  #   bounced    → straight back to confirmed. The mailbox was the problem;
  #                consent was never revoked, so a full re-opt-in would ask
  #                the reader to answer a question they already answered.
  #   complained → pending + a fresh double opt-in email. They flagged us —
  #                only their own click brings them back, never our say-so.
  # Anything else (unsubscribed, or not suppressed at all) is a no-op: an
  # explicit opt-out has no admin-side undo. Returns true when acted.
  def reactivate!(ip: nil)
    case status
    when "bounced"
      transaction do
        update!(status: :confirmed)
        log_event!("reactivated", ip:, source: "admin")
      end
      true
    when "complained"
      transaction do
        update!(status: :pending)
        log_event!("reinvited", ip:, source: "admin")
      end
      send_confirmation
      true
    else
      false
    end
  end

  # A spam complaint: the reader marked an issue as spam. Suppress like an
  # unsubscribe but as its own status — "marked us spam" and "asked to leave"
  # are different facts, and complaint rate is the reputation signal the
  # sending firewall will watch. The strongest suppression: it overrides
  # unsubscribed/bounced (a complaint is both true and more actionable), and
  # only a fresh double opt-in revives the row.
  def mark_complained!(source: nil)
    return if complained?

    transaction do
      update!(status: :complained)
      log_event!("complained", source:)
    end

    streams.active.find_each { |stream| stream.end!("complained") }
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

  # THE hygiene ladder — the create validation rejects on any non-nil answer,
  # and the signup rejection log names the layer that caught the address
  # (format / reserved_tld / disposable). Ordered cheapest-first.
  def self.rejection_reason(email_address)
    domain = domain_of(email_address)
    return "format" unless email_address.to_s.match?(URI::MailTo::EMAIL_REGEXP)
    return "reserved_tld" if domain.split(".").last.in?(RESERVED_TLDS)

    address = ValidEmail2::Address.new(email_address)
    return "format" unless address.valid?
    return "disposable" if address.disposable_domain? && !address.allow_listed?

    nil
  end

  def self.seed_domain?(email_address)
    domain = domain_of(email_address)
    SEED_DOMAINS.any? { |seed| domain == seed || domain.end_with?(".#{seed}") }
  end

  def self.domain_of(email_address) = email_address.to_s.split("@").last.to_s.downcase

  private
    def assign_person
      self.person ||= Person.find_or_initialize_by(email_address: email_address) if email_address.present?
    end

    def email_address_deliverable
      errors.add(:email_address, :invalid) if self.class.rejection_reason(email_address)
    end

    def flag_seed_domain
      self.seed = true if self.class.seed_domain?(email_address)
    end

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
