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
  # error      — validation stuck / provisioning failed (surface the reason)
  # disconnected — author removed it; KV key + custom hostname torn down
  STATUSES = %w[ pending verifying live error disconnected ].freeze

  validates :hostname, presence: true,
    uniqueness: { case_sensitive: false } # advisory; the unique index is authoritative
  validates :status, inclusion: { in: STATUSES }
  validate :hostname_is_acceptable, on: :create

  scope :connected, -> { where.not(status: "disconnected") }

  STATUSES.each { |s| define_method("#{s}?") { status == s } }

  # The KV value the edge Worker expects for this hostname: the plain account
  # slug, no JSON wrapper (edge/src/index.js reads it as a bare string).
  def kv_value = account.slug

  # Both statuses must be active before we call a domain live — a TLS handshake
  # can succeed before ssl.status flips, so "the site loaded" is not the signal.
  def provisioned? = status == "verifying" && cloudflare_status == "active" && ssl_status == "active"

  # Set from the poll job's fetched result (result.status), distinct from the
  # certificate's ssl_status; kept only to compute provisioned?.
  attr_accessor :cloudflare_status

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
