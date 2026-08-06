require "test_helper"

class AdminSendingDomainsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "index revives a dead status poll for a stale verifying domain" do
    accounts(:merovex).sending_domains.create!(domain: "news.merovex.press", status: "verifying",
      last_checked_at: 3.hours.ago)
    sign_in_as users(:admin)

    assert_enqueued_with(job: SendingDomainStatusJob) { get admin_sending_domains_path }
  end

  test "index renders the sending address, handle form, and connect form" do
    sign_in_as users(:admin)
    get admin_sending_domains_path
    assert_response :success
    assert_select "form"
    assert_match "noreply@#{Account.shared_sending_domain}", response.body
  end

  test "index shows DNS instructions for a verifying domain" do
    accounts(:merovex).sending_domains.create!(domain: "news.merovex.press", status: "verifying",
      dkim_tokens: %w[ tok1 tok2 tok3 ], mail_from_domain: "bounce.news.merovex.press")
    sign_in_as users(:admin)
    get admin_sending_domains_path
    assert_response :success
    assert_select ".field__label", text: /tok1\._domainkey\.news\.merovex\.press/
    assert_select ".copy-field__value[value=?]", "tok1.dkim.amazonses.com"
    assert_select ".field__label", text: /bounce\.news\.merovex\.press/
  end

  test "claiming a handle updates the sending address" do
    sign_in_as users(:admin)
    patch admin_handle_path, params: { handle: "merovex" }
    assert_redirected_to admin_sending_domains_path
    assert_equal "merovex", accounts(:merovex).reload.handle
  end

  test "a reserved handle is refused with the validation message" do
    sign_in_as users(:admin)
    patch admin_handle_path, params: { handle: "noreply" }
    assert_redirected_to admin_sending_domains_path
    assert_match(/reserved/, flash[:alert])
    assert_nil accounts(:merovex).reload.handle
  end
end
