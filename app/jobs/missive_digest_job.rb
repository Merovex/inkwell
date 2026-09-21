# Once-daily nudge to each site's owner: "you have X new contact messages",
# where X counts that site's Missives confirmed in the last day. No message
# content rides along — just the count and a link to the site's
# /admin/missives. A site with nothing new gets no email. Runs each morning
# (config/recurring.yml).
#
# Platform missives (no account — mail to the support desk) aren't digested:
# staff read those in the support desk view.
class MissiveDigestJob < ApplicationJob
  def perform
    # A deliberate cross-account sweep to find who has news; each email is
    # then one account's count, sent to that account's owner.
    counts = Current.allowing_unscoped_tenancy do
      Missive.confirmed.where(confirmed_at: 24.hours.ago..).where.not(account_id: nil).group(:account_id).count
    end

    Account.where(id: counts.keys).includes(:owner).find_each do |account|
      MissiveMailer.digest(account, counts[account.id]).deliver_later
    end
  end
end
