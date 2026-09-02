# Daily sweep that hard-deletes never-confirmed subscribers older than 30 days.
# The confirmation token expires after 7 days, so a month-old pending row is a
# dead opt-in (an admin can Resend before then to re-issue a fresh link). We
# destroy the row — cascading its consent events, streams, and deliveries — so
# the roster stays honest and we don't hold data an unconfirmed reader never
# fully consented to. Idempotent; a no-op when nothing is due. A deliberate
# cross-account sweep: age, not tenancy, decides.
class PendingSubscriberPurgeJob < ApplicationJob
  PURGE_AFTER = 30.days

  def perform
    Current.allowing_unscoped_tenancy do
      Subscriber.pending.where(created_at: ..PURGE_AFTER.ago).find_each(&:destroy)
    end
  end
end
