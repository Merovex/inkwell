# One connected hostname on the Cloudflare-for-SaaS path (onboarding step 1).
# The account owns several: the apex and its www. as separate rows, one flagged
# canonical. The hostname column's UNIQUE index (see the migration) is what
# stops two accounts claiming the same domain — the check that matters, because
# the last KV write would otherwise silently win.
class CustomDomain < ApplicationRecord
  belongs_to :account

  # pending    — row created, Cloudflare custom hostname + KV not yet written
  # verifying  — hostname created; waiting on DV-TXT + certificate (poll job)
  # live       — result.status AND result.ssl.status both active
  # error      — the poll chain ran out before this validated; nothing is
  #              watching it any more, and the page says so instead of showing
  #              a "verifying" that will never change on its own
  # disconnected — author removed it; KV key + custom hostname torn down
  STATUSES = %w[ pending verifying live error disconnected ].freeze

  # Still on its way to live: the poll may have stopped watching (error), but
  # a later check can still flip either of these.
  UNRESOLVED_STATUSES = %w[ verifying error ].freeze

  validates :hostname, presence: true,
    uniqueness: { case_sensitive: false } # advisory; the unique index is authoritative
  validates :status, inclusion: { in: STATUSES }
  validate :hostname_is_acceptable, on: :create

  scope :connected, -> { where.not(status: "disconnected") }
  scope :unresolved, -> { where(status: UNRESOLVED_STATUSES) }

  # The two halves of unresolved, split by whether a poll chain is watching.
  # That is the whole difference between them (see STATUSES), and naming it is
  # what lets a chain tell "still my job" from "another chain already gave up
  # on these" — the check that stops a page visit's redundant fork from
  # re-alerting on a stall someone already reported.
  scope :watched, -> { where(status: "verifying") }
  scope :unwatched, -> { where(status: "error") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # The DV TXT records Cloudflare is still waiting on, as value objects rather
  # than raw JSON hashes — see CustomDomain::ValidationRecord. Empty once the
  # certificate issues (Cloudflare stops listing them), which is exactly what
  # the DNS instructions should show: nothing left to add.
  def validation_records = ValidationRecord.wrap(super)

  def validation_records=(records)
    super(ValidationRecord.wrap(records).map(&:as_json))
  end

  # The KV value the edge Worker expects for this hostname: the plain account
  # slug, no JSON wrapper (edge/src/index.js reads it as a bare string).
  def kv_value = account.slug

  # Both statuses must be active before we call a domain live — a TLS handshake
  # can succeed before ssl.status flips, so "the site loaded" is not the signal.
  # (Learned the hard way: an author whose own zone proxies the hostname serves
  # a valid cert of their own while this one never validates.)
  #
  # cloudflare_status is the poll's fetched result.status — the hostname's own
  # verification state, distinct from the certificate's ssl_status. Persisted,
  # not an attr_accessor: it is half the evidence for provisioned?, and a
  # column is what lets that question be answered — and this row explained —
  # outside a live poll.
  # Cloudflare's hostname state has more than two values, and not every healthy
  # one is the literal "active" — a certificate rotation parks a perfectly good
  # hostname at "active_redeploying". Exact equality reads that as failure, and
  # permanently: nothing revisits a row that never flips.
  ACTIVE_HOSTNAME_STATUSES = %w[ active active_redeploying ].freeze

  # Either unresolved status can still flip: a row the poll gave up on (error)
  # validates the moment the author finally publishes the record, and the next
  # check must be allowed to notice.
  def provisioned?
    UNRESOLVED_STATUSES.include?(status) && ACTIVE_HOSTNAME_STATUSES.include?(cloudflare_status) &&
      ssl_status == "active"
  end

  # Why this row hasn't validated, read from public DNS (CustomDomain::Diagnosis).
  def diagnosis
    Diagnosis.new(self, cname_target: Rails.configuration.x.cloudflare.cname_target)
  end

  private
    def hostname_is_acceptable
      parsed = Hostname.new(hostname)
      if parsed.valid?
        self.hostname = parsed.normalized
      else
        errors.add(:hostname, parsed.error)
      end
    end
end
