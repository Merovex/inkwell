require "test_helper"

# Host-role routing under APP_HOST enforcement (ADR 0018). Enforcement is off
# by default in test — every other test exercises legacy single-tenant routing
# — so each test here switches it on and teardown always switches it back.
class HostRoutingTest < ActionDispatch::IntegrationTest
  APP_HOST = "kindredquill.example"

  setup do
    Rails.configuration.x.app_host = APP_HOST
    @account = accounts(:merovex)
  end

  teardown do
    Rails.configuration.x.app_host = nil
  end

  test "tenant domain serves its public site, www folding into the apex" do
    host! @account.domain
    get "/books"
    assert_response :success

    host! "www.#{@account.domain}"
    get "/books"
    assert_response :success
  end

  test "tenant domain no longer serves admin or sign-in" do
    host! @account.domain
    get "/admin"
    assert_response :not_found

    get "/session/new"
    assert_response :not_found
  end

  test "unknown host is a 404" do
    host! "stranger.example"
    get "/books"
    assert_response :not_found
  end

  test "slug-prefixed admin works for a member, and URLs carry the prefix" do
    host! APP_HOST
    sign_in_as users(:admin)

    get "/#{@account.slug}/admin/books"
    assert_response :success
    assert_select "a[href=?]", "/#{@account.slug}/admin/books/new"
  end

  test "slug lookup is Crockford-normalized" do
    host! APP_HOST
    sign_in_as users(:admin)

    get "/#{@account.slug.downcase}/admin/books"
    assert_response :success
  end

  test "unprefixed or unknown-slug admin on the app host is a 404" do
    host! APP_HOST
    sign_in_as users(:admin)

    get "/admin"
    assert_response :not_found

    get "/ZZZZZ9/admin"
    assert_response :not_found
  end

  test "the public site does not exist on the app host" do
    host! APP_HOST
    get "/books"
    assert_response :not_found
  end

  test "bare app host redirects to sign-in" do
    host! APP_HOST
    get "/"
    assert_redirected_to "/session/new"
  end

  test "signing in on the app host lands in the account's admin" do
    host! APP_HOST
    get verify_session_path(code: users(:admin).sign_in_codes.create!.plaintext)

    assert_redirected_to "http://#{APP_HOST}/#{@account.slug}/admin"
  end

  test "a non-member gets the same 404 as a wrong slug" do
    outsider = User.create!(email_address: "outsider@example.com", role: "domain_admin")
    host! APP_HOST
    sign_in_as outsider

    get "/#{@account.slug}/admin/books"
    assert_response :not_found
  end

  test "magic-link email points at the app host" do
    email = SessionMailer.magic_link(users(:admin), "ABCDEFGH")
    [ email.html_part, email.text_part ].each do |part|
      assert_includes part.body.to_s, "http://#{APP_HOST}/session/verify"
    end
  end
end
