require "test_helper"

class CustomDomainStatusJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  # Returns the given hostname/ssl statuses for every custom hostname it's asked
  # about — injected through the job's client_override seam. `validations` are
  # the txt_value strings Cloudflare is still listing, in the shape it uses.
  class FakeClient
    def initialize(status:, ssl_status:, validations: [])
      @status = status
      @ssl_status = ssl_status
      @validations = validations
    end

    def get_custom_hostname(id)
      Cloudflare::CustomHostname.new("id" => id, "status" => @status,
        "ssl" => { "status" => @ssl_status,
                   "validation_records" => @validations.map { |value|
                     { "txt_name" => "_acme-challenge.merovex.press", "txt_value" => value }
                   } })
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

  test "marks a domain the chain gave up on so the page can stop claiming it is verifying" do
    account = accounts(:merovex)
    domain = account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex")
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")

    capturing_alerts do
      CustomDomainStatusJob.perform_now(account, attempt: CustomDomainStatusJob::MAX_ATTEMPTS)
    end

    assert domain.reload.error?
  end

  test "a second chain forked by a page visit stops instead of re-reporting a stall" do
    account = accounts(:merovex)
    domain = account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex")
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")

    capturing_alerts do |alerts|
      # The chain that gets there first reports the stall and marks the row.
      CustomDomainStatusJob.perform_now(account, attempt: CustomDomainStatusJob::MAX_ATTEMPTS)
      assert_equal 1, alerts.size
      assert domain.reload.error?

      # A duplicate chain forked by an earlier page visit reaches the same
      # point later. Nothing is watching these rows any more, so it has
      # nothing to add — and must not page us a second time.
      assert_no_enqueued_jobs(only: CustomDomainStatusJob) do
        CustomDomainStatusJob.perform_now(account, attempt: CustomDomainStatusJob::MAX_ATTEMPTS)
      end

      assert_equal 1, alerts.size
    end
  end

  test "a duplicate chain mid-flight stops once another has given up on its rows" do
    account = accounts(:merovex)
    account.custom_domains.create!(hostname: "merovex.press", status: "error", cloudflare_id: "id-apex")
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")

    # Waking mid-chain (attempt > 1) is not a new watch, so the row stays
    # unwatched and the chain ends here rather than running out its own clock.
    assert_no_enqueued_jobs(only: CustomDomainStatusJob) do
      CustomDomainStatusJob.perform_now(account, attempt: 5)
    end
  end

  test "starting a chain resumes the watch on rows a previous one gave up on" do
    account = accounts(:merovex)
    domain = account.custom_domains.create!(hostname: "merovex.press", status: "error", cloudflare_id: "id-apex")
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "pending_validation")

    # Pressing "Check again" runs the job at attempt 1: the row goes back
    # under watch, and the page stops saying checking has stopped.
    assert_enqueued_with(job: CustomDomainStatusJob) do
      CustomDomainStatusJob.perform_now(account)
    end

    assert domain.reload.verifying?
  end

  test "a domain the chain gave up on is still polled, and can still go live" do
    account = accounts(:merovex)
    account.update!(domain: nil)
    domain = account.custom_domains.create!(hostname: "merovex.press", status: "error",
      cloudflare_id: "id-apex", canonical: true)
    CustomDomainStatusJob.client_override = FakeClient.new(status: "active", ssl_status: "active")

    CustomDomainStatusJob.perform_now(account)

    assert domain.reload.live?
  end

  test "stores every outstanding validation record, not just the first" do
    account = accounts(:merovex)
    domain = account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex")
    # A rotated order leaves the old and the new both pending; keeping only the
    # first hid the record that was actually blocking issuance.
    CustomDomainStatusJob.client_override = FakeClient.new(status: "active", ssl_status: "pending_validation",
      validations: %w[ old-token new-token ])

    CustomDomainStatusJob.perform_now(account)

    assert_equal %w[ old-token new-token ], domain.reload.validation_records.map(&:txt_value)
  end

  test "clears the validation records once the certificate issues" do
    account = accounts(:merovex)
    domain = account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex",
      validation_records: [ { "txt_name" => "_acme-challenge.merovex.press", "txt_value" => "spent" } ])
    # Cloudflare stops listing records once the cert is deployed. Keeping the
    # last one seen is what left a finished hostname demanding a dead token.
    CustomDomainStatusJob.client_override = FakeClient.new(status: "active", ssl_status: "active")

    CustomDomainStatusJob.perform_now(account)

    assert_empty domain.reload.validation_records
  end

  test "keeps the known records while Cloudflare is still minting them" do
    account = accounts(:merovex)
    domain = account.custom_domains.create!(hostname: "merovex.press", status: "verifying", cloudflare_id: "id-apex",
      validation_records: [ { "txt_name" => "_acme-challenge.merovex.press", "txt_value" => "minted" } ])
    # ssl "initializing" answers with no records yet; blanking here would wipe
    # instructions the author may be halfway through following.
    CustomDomainStatusJob.client_override = FakeClient.new(status: "pending", ssl_status: "initializing")

    CustomDomainStatusJob.perform_now(account)

    assert_equal %w[ minted ], domain.reload.validation_records.map(&:txt_value)
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
