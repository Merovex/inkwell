# One site's week, for the weekly digest email — the numbers behind a single
# per-site section of the mail (a user who owns several sites gets one section
# each). Pure read model over existing data: subscriber movement from the
# consent log + snapshots, sends from Broadcast, posts from the spine. `week_of`
# is the Monday the week starts on; the window runs Mon 00:00 → next Mon 00:00.
class WeeklyReport
  attr_reader :account, :week_of

  def initialize(account, week_of:)
    @account = account
    @week_of = week_of
  end

  def starts_on = week_of
  def ends_on = week_of + 7.days
  def window = SubscriberSnapshot.week_window(week_of)

  # --- Subscribers -----------------------------------------------------------

  # Up to eight weekly readings ending this week (the trend bars), oldest first.
  def snapshots
    @snapshots ||= account.subscriber_snapshots.chronological.where(week_of: ..week_of).last(8)
  end

  def trend = snapshots.map(&:confirmed_count)
  def confirmed_count = snapshots.last&.confirmed_count || account.subscribers.sendable.count

  # Net change against last week's reading; nil when there's no prior week yet.
  def confirmed_delta
    snapshots.size >= 2 ? snapshots[-1].confirmed_count - snapshots[-2].confirmed_count : nil
  end

  # People who entered the sendable pool this week, grouped by opt-in source
  # (drives "Both from the nav form"). nil source keys collapse to "direct".
  def joined_by_source
    @joined_by_source ||= joined_events.group("subscribers.source").count
      .transform_keys { |source| source.presence || "direct" }
  end

  def joined = joined_by_source.values.sum

  # Explicit opt-outs only (bounces/complaints show under the newsletter send).
  def unsubscribed
    @unsubscribed ||= events(%w[ unsubscribed ]).count
  end

  # --- Newsletter sends ------------------------------------------------------

  def sends
    @sends ||= account.broadcasts.where(sent_at: window).order(:sent_at).to_a
  end

  def sent_any? = sends.any?
  def delivered = sends.sum(&:delivered_count)
  def bounced = sends.sum(&:bounced_count)
  def complained = sends.sum(&:complained_count)
  def recipients = sends.sum(&:recipients_count)
  def bounce_rate = recipients.zero? ? 0.0 : bounced.to_f / recipients

  # The addresses that hard-bounced from this week's sends — shown so the owner
  # can recognize a stale contact ("old-address@sbcglobal.net").
  def bounced_addresses
    return [] if sends.empty?

    BroadcastDelivery.joins(:subscriber)
      .where(broadcast_id: sends.map(&:id), bounced_at: window)
      .pluck(Arel.sql("subscribers.email_address"))
  end

  # --- Posts -----------------------------------------------------------------

  def published_posts
    @published_posts ||= posts.where(status: "published", published_at: window)
      .order(published_at: :desc).to_a
  end

  # Recent published posts that were never emailed — the "14 haven't seen it"
  # nudge. One query: a missing-or-unsent broadcast is a left join, not a loop
  # (a broadcast row with no sent_at is a scheduled send, still unmailed).
  def unmailed_posts
    @unmailed_posts ||= posts.where(status: "published")
      .left_joins(record: :broadcast).where(broadcasts: { sent_at: nil })
      .order(published_at: :desc).limit(20).to_a
  end

  def scheduled_posts
    @scheduled_posts ||= posts.where(status: "scheduled").order(:published_at).to_a
  end

  def scheduled? = scheduled_posts.any?

  def emailed?(post) = post.record.broadcast&.sent? || false
  def recipients_for(post) = post.record.broadcast&.recipients_count

  # Page reads for a post this week, best-effort from Ahoy's $view events,
  # matched on the record's public slug in the event's page property. NOTE: the
  # property key/path shape depends on ahoy.js payloads — verify against real
  # events before trusting the number.
  def reads_for(post)
    Ahoy::Event
      .where(visit_id: account.ahoy_visits.select(:id), name: "$view", time: window)
      .where("json_extract(properties, '$.page') LIKE ?", "%#{post.record.to_slug}%")
      .count
  end

  # --- Send decision ---------------------------------------------------------

  # Worth mailing about? Any subscriber movement, a send, or a new post.
  def changed?
    sent_any? || joined.positive? || unsubscribed.positive? ||
      published_posts.any? || (confirmed_delta && confirmed_delta != 0)
  end

  private
    def posts = Post.current_in(account.records.active)

    def joined_events = events(SubscriptionEvent::JOINED)

    def events(actions)
      SubscriptionEvent.joins(:subscriber)
        .where(subscribers: { account_id: account.id })
        .where(action: actions, created_at: window)
    end
end
