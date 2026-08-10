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

      next unless user.owned_accounts
        .any? { |account| WeeklyReport.new(account, week_of: week_of).changed? }

      WeeklyDigestMailer.weekly(user, week_of).deliver_later
      user.update_column(:last_digest_at, Time.current)
    end
  end
end
