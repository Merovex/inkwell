# The roster's headline: how many people can be mailed right now, how that
# changed over the last month, where the new ones came from, and how many chose
# to leave over the last quarter.
#
# Counted from the consent log rather than the subscriber rows, using
# SubscriptionEvent's JOINED/DEPARTED — the same definitions the weekly digest
# reports, so the two can never tell different stories about one week. That also
# catches an arrival however it happened: a reader who confirms a web opt-in and
# one pushed by BookFunnel both log a `confirmed` event, and a partner re-push of
# someone already on the list logs nothing, so retries can't inflate the number.
#
# The windows are deliberately different lengths. Arrivals are frequent enough
# to read monthly; departures are rare, and a 30-day count of them would say
# "0" nearly every month, which teaches nothing. And departures are counted, not
# rated: one leaver out of a dozen readers is 8%, a number that alarms without
# informing. A rate wants a denominator in the hundreds.
class SubscriberMovement
  ARRIVALS  = 30.days
  DEPARTURES = 90.days

  # Explicit opt-outs only. A bounce is a dead mailbox and a complaint is worse
  # than churn; both have their own tab on the roster and their own line in the
  # digest's delivery report. This number answers "how many people chose to go".
  LEAVING = %w[ unsubscribed ].freeze

  def initialize(account, now: Time.current)
    @account = account
    @now = now
  end

  # Who would receive the next broadcast: confirmed, seeds excluded. The same
  # figure the post's email banner quotes, so the two pages agree.
  def sendable = @account.subscribers.sendable.count

  def joined = events(SubscriptionEvent::JOINED, ARRIVALS)

  def net = joined - events(SubscriptionEvent::DEPARTED, ARRIVALS)

  def departures = events(LEAVING, DEPARTURES)

  # New arrivals by where they came from, biggest first — "6 from BookFunnel,
  # 1 from the nav form". Grouped on the subscriber's current source, so a
  # reader who first arrived through a site form and later came through a
  # partner reads as the partner's.
  def joined_by_source
    scope(SubscriptionEvent::JOINED, ARRIVALS)
      .group("subscribers.source").count
      .transform_keys { |source| Subscriber.label_for_source(source) }
      .sort_by { |_source, count| -count }
  end

  private
    def events(actions, window) = scope(actions, window).count

    def scope(actions, window)
      SubscriptionEvent.for_account(@account)
        .where(action: actions, created_at: (@now - window)..@now)
    end
end
