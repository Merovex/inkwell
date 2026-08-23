# A reader's global identity: one row per email address across every press
# (ADR 0002 vocabulary; plan 1.6). A Subscriber is a person's membership in
# one press's list — deliveries, streams, and events all stay keyed by
# subscriber and never touch this table. Deliberately minimal.
class Person < ApplicationRecord
  has_many :subscribers

  normalizes :email_address, with: -> { it.strip.downcase }

  validates :email_address, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # The cross-site suppression ledger, read back as the send path's question
  # (ADR 0027) — the one thing the platform knows about a person beyond the
  # address itself.
  def reputation = Person::Reputation.new(self)
end
