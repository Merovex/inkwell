# Daily sweep that hard-deletes Missives past their life: anything confirmed
# more than 60 days ago (well past the 30-day Trash window), and any submission
# that was never confirmed within its short TTL (7 days) — so abandoned/spam
# opt-ins don't linger. Idempotent; a no-op when nothing is due.
class MissivePurgeJob < ApplicationJob
  def perform
    Missive.purgeable.delete_all
  end
end
