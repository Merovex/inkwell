# "Send a test" for the weekly digest: mails the current user their own digest
# right now so they can eyeball the real email in production. Includes every site
# they own (only_changed: false) so the template renders even in a quiet week.
# Platform staff only — a bare 404 for everyone else, like the support desk.
class User::DigestTestsController < ApplicationController
  require_root

  def create
    week_of = 1.week.ago.to_date.beginning_of_week
    # Every owned site, changed or not, so the template renders in a quiet week.
    WeeklyDigestMailer.weekly(Current.user, week_of, Current.user.owned_account_ids).deliver_later
    redirect_to user_settings_path, notice: "Test digest on its way to #{Current.user.email_address}."
  end
end
