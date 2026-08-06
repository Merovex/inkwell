require "test_helper"

class AdminCustomDomainsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
