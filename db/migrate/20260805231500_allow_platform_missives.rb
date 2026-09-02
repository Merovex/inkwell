# Platform support mail (support@kindredquill.com → SupportMailbox) belongs to
# the App, not to any Site: a nil account marks a platform missive, read by
# root staff at /missives on the app host. Site contact-form missives keep
# their account as before.
class AllowPlatformMissives < ActiveRecord::Migration[8.2]
  def change
    change_column_null :missives, :account_id, true
  end
end
