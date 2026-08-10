# One weekly reading of a site's sendable subscriber count — the baseline the
# weekly digest compares against ("Up 2 on last week") and the source of the
# eight-week trend bars. Captured by WeeklyDigestJob before it composes the mail;
# keyed on [account, week_of] so a re-run never doubles a week.
class SubscriberSnapshot < ApplicationRecord
  belongs_to :account

  scope :chronological, -> { order(:week_of) }

  # Record (or refresh) an account's reading for the week beginning `week_of`.
  # confirmed_count is the standing sendable total; joined/unsubscribed are that
  # week's movement, kept for history. Idempotent on [account_id, week_of].
  def self.capture(account, week_of:)
    window = week_of.beginning_of_day..(week_of + 7.days).beginning_of_day

    upsert(
      { account_id: account.id, week_of: week_of,
        confirmed_count: account.subscribers.sendable.count,
        joined_count: account_events(account, %w[ confirmed resubscribed reactivated ], window),
        unsubscribed_count: account_events(account, %w[ unsubscribed bounced complained ], window),
        created_at: Time.current, updated_at: Time.current },
      unique_by: %i[ account_id week_of ]
    )
  end

  # Count of subscriber consent events (by action) for one account in a window.
  # subscribers.account_id anchors the query for the tenancy guard.
  def self.account_events(account, actions, window)
    SubscriptionEvent.joins(:subscriber)
      .where(subscribers: { account_id: account.id })
      .where(action: actions, created_at: window)
      .count
  end
  private_class_method :account_events
end
