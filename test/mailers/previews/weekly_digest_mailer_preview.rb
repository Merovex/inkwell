# Preview at /rails/mailers/weekly_digest_mailer/weekly
class WeeklyDigestMailerPreview < ActionMailer::Preview
  def weekly
    user = User.joins(:owned_accounts).first || User.first
    WeeklyDigestMailer.weekly(user, 1.week.ago.to_date.beginning_of_week)
  end
end
