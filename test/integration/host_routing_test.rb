require "test_helper"

# Host-role routing under APP_HOST enforcement (ADR 0018/0019). Enforcement is
# off by default in test — every other test exercises legacy single-tenant
# routing — so each test here switches it on and teardown switches it back.
class HostRoutingTest < ActionDispatch::IntegrationTest
  APP_HOST = "app.kindredquill.example"

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

  test "the app host disallows crawlers" do
    host! APP_HOST
    get "/robots.txt"
    assert_response :success
    assert_match "Disallow: /", response.body
  end

  test "bare app host forces authentication" do
    host! APP_HOST
    get "/"
    assert_redirected_to "/session/new"
  end

  # Apex-public serving is retired (Phase 2): the apex points at the static
  # marketing site and a domain-less account lives on sites.kindredquill.com/
  # <handle>, so the app itself no longer answers on the apex at all.
  test "the apex is not served by the app" do
    host! "kindredquill.example"
    get "/anything?x=1"
    assert_response :not_found
  end

  test "a domain-less account is no longer served from the apex under its slug" do
    domainless = Account.create!(name: "Nameless Site", owner: users(:bob))
    host! "kindredquill.example"

    get "/#{domainless.slug}/books"
    assert_response :not_found
  end

  test "signed in with one account, the root and /SLUG land in its admin" do
    host! APP_HOST
    sign_in_as users(:admin)

    get "/"
    assert_redirected_to "http://#{APP_HOST}/#{@account.slug}/admin"

    get "/#{@account.slug}"
    assert_redirected_to "/#{@account.slug}/admin"
  end

  test "signed in with several accounts, the root offers picker cards" do
    second = Account.create!(name: "Second Press", owner: users(:admin))
    AccountUser.create!(account: second, user: users(:admin))

    host! APP_HOST
    sign_in_as users(:admin)
    get "/"

    assert_response :success
    assert_select ".account-picker__card", 2
    assert_select ".account-picker__card[href=?]", "/#{second.slug}/admin", text: /Second Press/
  end

  test "signing in on the app host lands in the account's admin" do
    host! APP_HOST
    get verify_session_path(code: users(:admin).sign_in_codes.create!.plaintext)

    assert_redirected_to "http://#{APP_HOST}/#{@account.slug}/admin"
  end

  test "a non-member gets the same 404 as a wrong slug" do
    outsider = User.create!(email_address: "outsider@example.com")
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
