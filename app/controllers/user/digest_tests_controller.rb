# "Send a test" for the weekly digest: mails the current user their own digest
# right now so they can eyeball the real email in production. Includes every site
# they own (only_changed: false) so the template renders even in a quiet week.
class User::DigestTestsController < ApplicationController
  def create
    week_of = 1.week.ago.to_date.beginning_of_week
    WeeklyDigestMailer.weekly(Current.user, week_of, only_changed: false).deliver_later
    redirect_to user_settings_path, notice: "Test digest on its way to #{Current.user.email_address}."
  end
end
