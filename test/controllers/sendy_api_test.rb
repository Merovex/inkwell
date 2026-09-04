require "test_helper"

# The rest of Sendy's API that BookFunnel calls: the count it verifies your
# settings with, and the status it asks before letting a reader through a
# restricted page. Both are POSTs that only read — Sendy's convention — and
# both answer plain text with a 200, errors included.
class SendyApiTest < ActionDispatch::IntegrationTest
  COUNT_PATH  = "/api/subscribers/active-subscriber-count.php"
  STATUS_PATH = "/api/subscribers/subscription-status.php"

  setup do
    @account = accounts(:merovex)
    @key = @account.sendy_api_key!
  end

  # ── active-subscriber-count.php ───────────────────────────────────────────

  test "counts the sendable list" do
    Current.with_account(@account) do
      Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel")
      Subscriber.opt_in(email_address: "pending@example.com")                       # unconfirmed
      Subscriber.opt_in_confirmed(email_address: "check@mail-tester.com", source: "bookfunnel") # seed
    end

    post COUNT_PATH, params: { api_key: @key, list_id: @account.slug }

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_equal "1", response.body, "confirmed readers only — no pending, no seeds"
  end

  test "counts nothing as zero rather than erroring" do
    post COUNT_PATH, params: { api_key: @key, list_id: @account.slug }

    assert_equal "0", response.body
  end

  test "the count reports Sendy's own key and list errors" do
    post COUNT_PATH, params: { list_id: @account.slug }
    assert_equal "API key not passed", response.body

    post COUNT_PATH, params: { api_key: "wrong", list_id: @account.slug }
    assert_equal "Invalid API key", response.body

    post COUNT_PATH, params: { api_key: @key }
    assert_equal "List ID not passed", response.body

    post COUNT_PATH, params: { api_key: @key, list_id: "somebody-else" }
    assert_equal "List does not exist", response.body
  end

  test "one site's key cannot count another site's list" do
    other = Account.create!(name: "Second Press", owner: users(:bob))
    Current.with_account(other) { Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel") }

    post COUNT_PATH, params: { api_key: @key, list_id: other.slug }

    assert_equal "List does not exist", response.body
  end

  # ── subscription-status.php ───────────────────────────────────────────────

  test "reports each of our statuses in Sendy's vocabulary" do
    expected = { confirmed: "Subscribed", pending: "Unconfirmed", unsubscribed: "Unsubscribed",
                 bounced: "Bounced", complained: "Complained" }

    expected.each_with_index do |(status, sendy_word), index|
      email = "reader#{index}@example.com"
      Current.with_account(@account) do
        Subscriber.opt_in(email_address: email).update!(status: status)
      end

      post STATUS_PATH, params: { api_key: @key, list_id: @account.slug, email: email }

      assert_equal sendy_word, response.body, "#{status} should read as #{sendy_word}"
    end
  end

  test "an address nobody has seen is not on the list" do
    post STATUS_PATH, params: { api_key: @key, list_id: @account.slug, email: "stranger@example.com" }

    assert_equal "Email does not exist in list", response.body
  end

  test "the status lookup normalizes the address like every other door" do
    Current.with_account(@account) { Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel") }

    post STATUS_PATH, params: { api_key: @key, list_id: @account.slug, email: "  Reader@Example.COM  " }

    assert_equal "Subscribed", response.body
  end

  test "the status reports Sendy's own key, list and email errors" do
    post STATUS_PATH, params: { list_id: @account.slug, email: "reader@example.com" }
    assert_equal "API key not passed", response.body

    post STATUS_PATH, params: { api_key: "wrong", list_id: @account.slug, email: "reader@example.com" }
    assert_equal "Invalid API key", response.body

    post STATUS_PATH, params: { api_key: @key, email: "reader@example.com" }
    assert_equal "List ID not passed", response.body

    post STATUS_PATH, params: { api_key: @key, list_id: @account.slug }
    assert_equal "Email not passed", response.body

    post STATUS_PATH, params: { api_key: @key, list_id: "somebody-else", email: "reader@example.com" }
    assert_equal "List does not exist", response.body
  end

  test "one site's key cannot read another site's subscriber" do
    other = Account.create!(name: "Second Press", owner: users(:bob))
    Current.with_account(other) { Subscriber.opt_in_confirmed(email_address: "reader@example.com", source: "bookfunnel") }

    post STATUS_PATH, params: { api_key: @key, list_id: other.slug, email: "reader@example.com" }

    assert_equal "List does not exist", response.body
  end

  test "both answer on the enforced app host, where BookFunnel points" do
    Rails.configuration.x.app_host = "app.kindredquill.example"
    host! "app.kindredquill.example"

    post COUNT_PATH, params: { api_key: @key, list_id: @account.slug }
    assert_equal "0", response.body

    post STATUS_PATH, params: { api_key: @key, list_id: @account.slug, email: "stranger@example.com" }
    assert_equal "Email does not exist in list", response.body
  ensure
    Rails.configuration.x.app_host = nil
  end
end
