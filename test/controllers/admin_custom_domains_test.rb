require "test_helper"

class AdminCustomDomainsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # Answers every poll with the given statuses (the job test's fake, local so
  # this file runs standalone).
  class FakeCloudflare
    def initialize(status:, ssl_status:) = (@status, @ssl_status = status, ssl_status)

    def get_custom_hostname(id)
      Cloudflare::CustomHostname.new("id" => id, "status" => @status, "ssl" => { "status" => @ssl_status })
    end
  end

  test "index revives a dead status poll for a stale verifying domain" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", last_checked_at: 3.hours.ago)
    sign_in_as users(:admin)

    assert_enqueued_with(job: CustomDomainStatusJob) { get admin_custom_domains_path }
  end

  test "index leaves a freshly-polled domain alone" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", last_checked_at: 1.minute.ago)
    sign_in_as users(:admin)

    assert_no_enqueued_jobs(only: CustomDomainStatusJob) { get admin_custom_domains_path }
  end

  test "the check badge re-polls inline and reports the flip" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", last_checked_at: Time.current)
    CustomDomainStatusJob.client_override = FakeCloudflare.new(status: "active", ssl_status: "active")
    sign_in_as users(:admin)

    post admin_custom_domain_check_path
    assert_redirected_to admin_custom_domains_path
    assert_match(/live/, flash[:notice])
    assert accounts(:merovex).custom_domains.reload.all?(&:live?)
  ensure
    CustomDomainStatusJob.client_override = nil
  end

  # No zone at all, so every lookup comes back empty — enough to reach a
  # verdict without asking the real network.
  class SilentResolver
    def getresources(*) = []
  end

  test "the check badge names why a domain is stuck instead of just saying it waited" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", txt_name: "_cf-custom-hostname.www.merovex.press", txt_value: "tv")
    CustomDomainStatusJob.client_override = FakeCloudflare.new(status: "pending", ssl_status: "pending_validation")
    CustomDomain::Diagnosis.resolver_override = SilentResolver.new
    sign_in_as users(:admin)

    post admin_custom_domain_check_path
    assert_redirected_to admin_custom_domains_path
    assert_match(/www\.merovex\.press isn't resolving yet/, flash[:notice])
  ensure
    CustomDomainStatusJob.client_override = nil
    CustomDomain::Diagnosis.resolver_override = nil
  end

  test "the poll persists the hostname's own status, not just the certificate's" do
    domain = accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id")
    CustomDomainStatusJob.client_override = FakeCloudflare.new(status: "active", ssl_status: "pending_validation")

    CustomDomainStatusJob.perform_now(accounts(:merovex))

    # Both halves of provisioned? survive the poll, so the row can be explained
    # later without asking Cloudflare again.
    assert_equal "active", domain.reload.cloudflare_status
    assert_equal "pending_validation", domain.ssl_status
    assert_not domain.provisioned?
  ensure
    CustomDomainStatusJob.client_override = nil
  end

  test "index renders the connect form" do
    sign_in_as users(:admin)
    get admin_custom_domains_path
    assert_response :success
    assert_select "form"
  end

  test "index shows DNS instructions for a verifying domain" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", txt_name: "_cf-custom-hostname.www.merovex.press", txt_value: "tv")
    sign_in_as users(:admin)
    get admin_custom_domains_path
    assert_response :success
    assert_select ".field__label", text: /_cf-custom-hostname\.www\.merovex\.press/
    assert_select ".copy-field__value[value=?]", "tv"
    assert_select ".copy-field__value[value=?]", Rails.configuration.x.cloudflare.cname_target
  end
end
