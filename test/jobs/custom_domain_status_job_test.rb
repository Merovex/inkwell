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

  # Answers as though the hostname's CNAME already points at the platform
  # target — routing done, certificate not.
  class RoutedZone
    def getresources(name, type)
      return [] unless type == Resolv::DNS::Resource::IN::CNAME
      [ Struct.new(:name).new(Rails.configuration.x.cloudflare.cname_target) ]
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

  test "bridges the build target as soon as DNS routes, without waiting on the certificate" do
    account = accounts(:merovex)
    account.update!(domain: nil)
    account.custom_domains.create!(hostname: "www.merovex.press", status: "verifying",
      cloudflare_id: "id-www", canonical: true)
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")
    CustomDomain::Diagnosis.resolver_override = RoutedZone.new

    CustomDomainStatusJob.perform_now(account)

    # Still not live — but the site is reachable at the domain, so builds must
    # target it or every asset URL 404s at the root.
    assert account.custom_domains.reload.all?(&:verifying?)
    assert_equal "merovex.press", account.reload.domain
  end

  test "leaves the build target alone while DNS still points elsewhere" do
    account = accounts(:merovex)
    account.update!(domain: nil)
    account.custom_domains.create!(hostname: "www.merovex.press", status: "verifying",
      cloudflare_id: "id-www", canonical: true)
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")

    CustomDomainStatusJob.perform_now(account) # default test zone resolves nothing

    assert_nil account.reload.domain
  end

  test "alerts instead of going quiet when the poll chain runs out" do
    account = accounts(:merovex)
    account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex")
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")

    capturing_alerts do |alerts|
      assert_no_enqueued_jobs(only: CustomDomainStatusJob) do
        CustomDomainStatusJob.perform_now(account, attempt: CustomDomainStatusJob::MAX_ATTEMPTS)
      end

      assert_equal 1, alerts.size
      # The alert carries the worked-out DNS reason, so it is actionable on sight.
      assert_equal :unresolved, alerts.dig(0, 1, :context, :domains, 0, :diagnosis)
    end
  end

  private
    # Minitest 6 dropped the bundled mock library; swapping the module method
    # by hand keeps this from needing a gem.
    def capturing_alerts
      captured = []
      original = Honeybadger.method(:notify)
      Honeybadger.define_singleton_method(:notify) { |message, **context| captured << [ message, context ] }
      yield captured
    ensure
      Honeybadger.define_singleton_method(:notify, original)
    end
end
