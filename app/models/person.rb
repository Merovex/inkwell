# A reader's global identity: one row per email address across every press
# (ADR 0002 vocabulary; plan 1.6). A Subscriber is a person's membership in
# one press's list — deliveries, streams, and events all stay keyed by
# subscriber and never touch this table. Deliberately minimal.
class Person < ApplicationRecord
  has_many :subscribers
  # The cross-site suppression ledger (ADR 0027) — the one thing the platform
  # knows about a person beyond the address itself.
  has_many :suppressions

  normalizes :email_address, with: -> { it.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # On the global list: hard-bounced, or complained against enough sites.
  def suppressed? = suppressions.in_force_for.exists?

  # Unmailable by this site: globally suppressed, or suppressed for it alone.
  def suppressed_for?(account) = suppressions.in_force_for(account).exists?
end
