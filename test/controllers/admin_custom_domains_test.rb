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
      status: "verifying", cloudflare_id: "id", last_checked_at: 1.minute.ago,
      validation_records: [ { "txt_name" => "_acme-challenge.www.merovex.press", "txt_value" => "tv" } ])
    sign_in_as users(:admin)

    assert_no_enqueued_jobs(only: CustomDomainStatusJob) { get admin_custom_domains_path }
  end

  test "the shorter leash for a record-less row still can't storm" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", validation_records: [], last_checked_at: 5.seconds.ago)
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

  test "the check badge names why a domain is stuck instead of just saying it waited" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id",
      validation_records: [ { "txt_name" => "_acme-challenge.www.merovex.press", "txt_value" => "tv" } ])
    CustomDomainStatusJob.client_override = FakeCloudflare.new(status: "pending", ssl_status: "pending_validation")
    sign_in_as users(:admin)

    post admin_custom_domain_check_path
    assert_redirected_to admin_custom_domains_path
    assert_match(/www\.merovex\.press isn't resolving yet/, flash[:notice])
  ensure
    CustomDomainStatusJob.client_override = nil
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
      status: "verifying", cloudflare_id: "id",
      validation_records: [ { "txt_name" => "_acme-challenge.www.merovex.press", "txt_value" => "tv" } ])
    sign_in_as users(:admin)
    get admin_custom_domains_path
    assert_response :success
    assert_select ".field__label", text: /_acme-challenge\.www\.merovex\.press/
    assert_select ".copy-field__value[value=?]", "tv"
    assert_select ".copy-field__value[value=?]", Rails.configuration.x.cloudflare.cname_target
  end

  test "index shows every outstanding validation record for a hostname" do
    # The bug this replaces: only the first was ever rendered, so the record
    # actually blocking issuance stayed invisible and the author added the one
    # they already had, forever.
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id",
      validation_records: [ { "txt_name" => "_acme-challenge.www.merovex.press", "txt_value" => "already-published" },
                            { "txt_name" => "_acme-challenge.www.merovex.press", "txt_value" => "the-blocking-one" } ])
    sign_in_as users(:admin)

    get admin_custom_domains_path

    assert_select ".copy-field__value[value=?]", "already-published"
    assert_select ".copy-field__value[value=?]", "the-blocking-one"
    # And says they coexist, so nobody replaces one with the other.
    assert_select "p", text: /add every value/
  end

  test "index stops asking for records from a hostname that is already live" do
    account = accounts(:merovex)
    account.custom_domains.create!(hostname: "merovex.press", status: "live", cloudflare_id: "id-apex",
      validation_records: [ { "txt_name" => "_acme-challenge.merovex.press", "txt_value" => "spent" } ])
    account.custom_domains.create!(hostname: "www.merovex.press", canonical: true, status: "verifying",
      cloudflare_id: "id-www",
      validation_records: [ { "txt_name" => "_acme-challenge.www.merovex.press", "txt_value" => "still-needed" } ])
    sign_in_as users(:admin)

    get admin_custom_domains_path

    assert_select ".copy-field__value[value=?]", "still-needed"
    assert_select ".copy-field__value[value=?]", "spent", false,
      "a live hostname must stop advertising its spent DV token"
  end

  test "index says so when the poll has given up instead of showing a waiting badge" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "error", cloudflare_id: "id", last_checked_at: 1.minute.ago)
    sign_in_as users(:admin)

    get admin_custom_domains_path

    assert_select ".alert--warning", text: /Automatic checking has stopped/
    assert_select ".check-badge", text: /Check again/
  end

  test "index re-reads promptly when a row has no records to show at all" do
    # The page has nothing to tell the author in this state, so it must not sit
    # on the routine ten-minute leash waiting to find out.
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", validation_records: [], last_checked_at: 2.minutes.ago)
    sign_in_as users(:admin)

    assert_enqueued_with(job: CustomDomainStatusJob) { get admin_custom_domains_path }
  end

  test "index doesn't claim missing records are still being issued" do
    # They may well be issued already and simply unread on our side — telling
    # the author to wait leaves them nothing to do and nothing to see.
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "verifying", cloudflare_id: "id", validation_records: [], last_checked_at: 1.second.ago)
    sign_in_as users(:admin)

    get admin_custom_domains_path

    assert_select "p", text: /press Check again/
    assert_select "p", text: /still being issued/, count: 0
  end

  test "index revives the poll for a domain the chain gave up on" do
    accounts(:merovex).custom_domains.create!(hostname: "www.merovex.press", canonical: true,
      status: "error", cloudflare_id: "id", last_checked_at: 3.hours.ago)
    sign_in_as users(:admin)

    assert_enqueued_with(job: CustomDomainStatusJob) { get admin_custom_domains_path }
  end
end
