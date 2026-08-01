require "test_helper"

class CustomDomainStatusJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Returns the given hostname/ssl statuses for every custom hostname it's asked
  # about — injected through the job's client_override seam.
  class FakeClient
    def initialize(status:, ssl_status:)
      @status = status
      @ssl_status = ssl_status
    end

    def get_custom_hostname(id)
      Cloudflare::CustomHostname.new("id" => id, "status" => @status, "ssl" => { "status" => @ssl_status })
    end
  end

  teardown { CustomDomainStatusJob.client_override = nil }

  test "goes live, bridges account.domain, and emails when both statuses are active" do
    account = accounts(:merovex)
    account.update!(domain: nil)
    account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex")
    account.custom_domains.create!(hostname: "www.merovex.press", status: "verifying", cloudflare_id: "id-www", canonical: true)

    CustomDomainStatusJob.client_override = FakeClient.new(status: "active", ssl_status: "active")
    assert_enqueued_emails 1 do
      CustomDomainStatusJob.perform_now(account)
    end

    assert account.custom_domains.reload.all?(&:live?)
    assert_equal "merovex.press", account.reload.domain
  end

  test "re-enqueues itself while a certificate is still validating" do
    account = accounts(:merovex)
    account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex")

    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")
    assert_enqueued_with(job: CustomDomainStatusJob) do
      CustomDomainStatusJob.perform_now(account)
    end

    assert account.custom_domains.reload.all?(&:verifying?)
  end
end
