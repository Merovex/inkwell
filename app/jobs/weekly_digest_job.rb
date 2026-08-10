# The Monday-morning weekly digest (config/recurring.yml). Two passes:
#   1. capture this week's subscriber snapshot for every account (the trend +
#      the baseline next week compares against), then
#   2. for each user still receiving a digest and due this run, compose one mail
#      across the sites they own — but only the sites with something to report,
#      and only if at least one does.
# Runs account-less like the other recurring jobs; every query is account-anchored.
class WeeklyDigestJob < ApplicationJob
  def perform(week_of: 1.week.ago.to_date.beginning_of_week)
    Account.find_each { |account| SubscriberSnapshot.capture(account, week_of: week_of) }

    User.digest_subscribers.find_each do |user|
      next unless user.digest_due?

      # The sites with something to report — decided once, here; the mailer
      # renders exactly these (ids, because reports don't serialize).
      active_ids = user.owned_accounts
        .select { |account| WeeklyReport.new(account, week_of: week_of).changed? }.map(&:id)
      next if active_ids.empty?

      WeeklyDigestMailer.weekly(user, week_of, active_ids).deliver_later
      user.touch(:last_digest_at)
    end
  end
end
