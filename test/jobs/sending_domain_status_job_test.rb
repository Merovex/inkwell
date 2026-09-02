require "test_helper"

class SendingDomainStatusJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Returns the given verification statuses for every identity it's asked
  # about — injected through the job's client_override seam.
  class FakeClient
    def initialize(dkim_status:, mail_from_status:)
      @dkim_status = dkim_status
      @mail_from_status = mail_from_status
    end

    def get_identity(domain)
      Ses::Client::Identity.new(dkim_tokens: %w[ token1 token2 token3 ],
        dkim_status: @dkim_status, mail_from_status: @mail_from_status)
    end
  end

  teardown { SendingDomainStatusJob.client_override = nil }

  test "goes live and emails the author when DKIM and MAIL FROM both verify" do
    account = accounts(:merovex)
    account.sending_domains.create!(domain: "news.merovex.press", status: "verifying",
      mail_from_domain: "bounce.news.merovex.press")

    SendingDomainStatusJob.client_override = FakeClient.new(dkim_status: "SUCCESS", mail_from_status: "SUCCESS")
    assert_enqueued_emails 1 do
      SendingDomainStatusJob.perform_now(account)
    end

    assert account.sending_domains.reload.all?(&:live?)
  end

  test "re-enqueues itself while DNS is still propagating" do
    account = accounts(:merovex)
    account.sending_domains.create!(domain: "news.merovex.press", status: "verifying")

    SendingDomainStatusJob.client_override = FakeClient.new(dkim_status: "PENDING", mail_from_status: "PENDING")
    assert_enqueued_with(job: SendingDomainStatusJob) do
      SendingDomainStatusJob.perform_now(account)
    end

    assert account.sending_domains.reload.all?(&:verifying?)
  end

  test "backfills DKIM tokens onto the row" do
    account = accounts(:merovex)
    domain = account.sending_domains.create!(domain: "news.merovex.press", status: "verifying")

    SendingDomainStatusJob.client_override = FakeClient.new(dkim_status: "PENDING", mail_from_status: "PENDING")
    SendingDomainStatusJob.perform_now(account)

    assert_equal %w[ token1 token2 token3 ], domain.reload.dkim_tokens
  end
end
