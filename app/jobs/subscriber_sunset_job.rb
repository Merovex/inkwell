# Weekly list hygiene (ADR 0014): nudge cold subscribers, then drop the ones who
# ignore the nudge. Idempotent — re-running never double-nudges (the nudge is
# once, guarded by re_engagement_sent_at) or double-drops (unsubscribe! is a
# no-op once unsubscribed). Inert until open/click tracking is live
# (Subscriber.sunset_enabled?), so we never sunset a list on absent engagement
# data. Runs Monday mornings (config/recurring.yml).
class SubscriberSunsetJob < ApplicationJob
  def perform
    return unless Subscriber.sunset_enabled?

    # Cheap prefilter: skip the freshly-engaged. The per-row thresholds
    # (later-of days/emails) are then evaluated in sunset_action.
    Subscriber.confirmed
      .where("last_engaged_at IS NULL OR last_engaged_at < ?", Subscriber::RE_ENGAGE_DAYS.days.ago)
      .find_each do |subscriber|
        case subscriber.sunset_action
        when :re_engage then subscriber.send_re_engagement
        when :drop      then subscriber.unsubscribe!(source: "sunset")
        end
      end
  end
end
