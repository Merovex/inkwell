require "test_helper"

class MissiveDigestJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @merovex = accounts(:merovex)
    @rival_owner = User.create!(email_address: "rival@example.com", name: "Rival Owner")
    @rival = Account.create!(name: "Rival Press", owner: @rival_owner, domain: "rival.example")
  end

  test "each site's owner gets their own count, linked to their own admin" do
    2.times { |i| missive(@merovex, "one-#{i}") }
    missive(@rival, "theirs")

    perform_enqueued_jobs { MissiveDigestJob.perform_now }

    mails = ActionMailer::Base.deliveries.last(2).index_by { it.to.sole }
    ours, theirs = mails.fetch(@merovex.owner.email_address), mails.fetch("rival@example.com")

    assert_equal "2 new contact messages — Merovex Press", ours.subject
    assert_includes ours.text_part.body.to_s, "/#{@merovex.slug}/admin/missives"
    assert_equal "1 new contact message — Rival Press", theirs.subject
    assert_includes theirs.text_part.body.to_s, "/#{@rival.slug}/admin/missives"
  end

  test "a site with nothing new — or only old or unconfirmed mail — gets no email" do
    missive(@merovex, "stale", confirmed_at: 2.days.ago)
    missive(@merovex, "unconfirmed", confirmed_at: nil)

    assert_no_enqueued_emails { MissiveDigestJob.perform_now }
  end

  test "platform missives aren't digested — staff read them in the support desk" do
    Current.without_account do
      Missive.create!(account: nil, name: "Fan", email_address: "fan@example.com", subject: "help", body: "hi",
        confirmed_at: Time.current)
    end

    assert_no_enqueued_emails { MissiveDigestJob.perform_now }
  end

  private
    def missive(account, subject, confirmed_at: Time.current)
      Current.with_account(account) do
        Missive.create!(name: "Fan", email_address: "fan@example.com", subject: subject, body: "hello",
          confirmed_at: confirmed_at)
      end
    end
end
