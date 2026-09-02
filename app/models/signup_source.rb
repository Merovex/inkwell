# The identity-free residue of a consent action: which site, from which
# source neighborhood (SubscriptionEvent.fingerprint), doing what, when. No
# email, no person, no IP, no subscriber — so it can outlive the subscriber
# whose event it shadows. That is its whole reason to exist: never-confirmed
# opt-ins are purged at 30 days (PendingSubscriberPurgeJob) and are exactly the
# population a cluster query (many signups, many sites, one source, one burst)
# wants to see; this row keeps the source signal after the address is gone.
# Append-only, platform-wide, read across accounts by design. ADR 0026.
class SignupSource < ApplicationRecord
  belongs_to :account

  validates :source_fingerprint, presence: true
  validates :action, inclusion: { in: SubscriptionEvent::ACTIONS }

  before_update { raise ActiveRecord::ReadOnlyRecord, "signup sources are append-only" }

  # Shadow a consent event that carries a fingerprint; events with no IP
  # (admin actions, webhook bounces) leave no trace.
  def self.trace(event)
    return unless event.source_fingerprint

    create!(account: event.subscriber.account, source_fingerprint: event.source_fingerprint,
      action: event.action, created_at: event.created_at)
  end
end
