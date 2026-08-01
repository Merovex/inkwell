require "test_helper"

class AdminCustomDomainsTest < ActionDispatch::IntegrationTest
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
    assert_select "code", text: "_cf-custom-hostname.www.merovex.press"
    assert_match Rails.configuration.x.cloudflare.cname_target, response.body
  end
end
