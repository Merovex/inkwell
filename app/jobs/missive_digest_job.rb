# Once-daily nudge to the domain admins: "you have X new contact messages",
# where X counts Missives confirmed in the last day. No message content rides
# along — just the count and a link to /admin/missives. Skips the send entirely
# when nothing new arrived, or when there are no admins to tell. Runs each
# morning (config/recurring.yml).
class MissiveDigestJob < ApplicationJob
  def perform
    count = Missive.confirmed.where(confirmed_at: 24.hours.ago..).count
    return if count.zero?

    recipients = User.domain_admin.pluck(:email_address)
    return if recipients.empty?

    MissiveMailer.digest(recipients, count).deliver_later
  end
end
