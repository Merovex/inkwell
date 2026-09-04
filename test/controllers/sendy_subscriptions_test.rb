require "test_helper"

# The Sendy-compatible subscribe endpoint BookFunnel pushes readers to. Every
# assertion here is against Sendy's own contract (sendy.co/api): plain text,
# HTTP 200, even for the failures.
class SendySubscriptionsTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:merovex)
    @key = @account.sendy_api_key!
  end

  test "subscribes a reader and answers Sendy's 1" do
    assert_difference -> { @account.subscribers.count }, 1 do
      post subscribe_path, params: { api_key: @key, email: "reader@example.com", name: "Nia", list: @account.slug }
    end

    assert_response :success
    assert_equal "1", response.body
    assert_equal "text/plain", response.media_type

    subscriber = @account.subscribers.sole
    assert subscriber.confirmed?, "BookFunnel only pushes confirmed, consented readers"
    assert subscriber.confirmed_at
    assert_equal "bookfunnel", subscriber.source
    assert_equal %w[subscribed confirmed], subscriber.events.pluck(:action)
  end

  test "answers true instead of 1 when the caller asks for boolean" do
    post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: @account.slug, boolean: "true" }

    assert_equal "true", response.body
  end

  test "stores the consent evidence BookFunnel sends" do
    post subscribe_path, params: {
      api_key: @key, email: "reader@example.com", list: @account.slug,
      ipaddress: "103.219.21.105", country: "GB", gdpr: "true",
      referrer: "https://dl.bookfunnel.com/the-bargain"
    }

    subscriber = @account.subscribers.sole
    assert_equal "103.219.21.105", subscriber.consent_ip, "the reader's IP, not BookFunnel's server"
    assert_equal "GB", subscriber.country_code
    assert subscriber.gdpr_country
    assert_equal "https://dl.bookfunnel.com/the-bargain", subscriber.source_url
    assert_equal "103.219.21.105", subscriber.events.first.ip_address
  end

  test "reads BookFunnel's own field names and its YES/NO spelling" do
    post subscribe_path, params: {
      api_key: @key, email: "reader@example.com", list: @account.slug,
      country: "United States of America", country_code: "us", is_eu_country: "NO"
    }

    subscriber = @account.subscribers.sole
    assert_equal "US", subscriber.country_code, "the code, upcased — never the spelled-out country"
    assert_equal false, subscriber.gdpr_country, "NO must not read as true"
  end

  test "leaves the GDPR flag unknown when nothing says either way" do
    post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: @account.slug }

    assert_nil @account.subscribers.sole.gdpr_country
  end

  test "ignores the Sendy params we have no use for" do
    post subscribe_path, params: {
      api_key: @key, email: "reader@example.com", list: @account.slug,
      silent: "true", hp: "", gdpr: "true", name: "Nia"
    }

    assert_equal "1", response.body
  end

  test "is idempotent — a retried push subscribes once and still answers 1" do
    2.times do
      post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: @account.slug }
    end

    assert_equal "1", response.body
    assert_equal 1, @account.subscribers.count
    assert_equal %w[subscribed confirmed], @account.subscribers.sole.events.pluck(:action)
  end

  test "confirms an address that was still waiting on our own double opt-in" do
    subscriber = Current.with_account(@account) { Subscriber.opt_in(email_address: "reader@example.com", source: "hero") }
    assert subscriber.pending?

    post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: @account.slug }

    assert subscriber.reload.confirmed?
    assert_equal %w[subscribed confirmed], subscriber.events.pluck(:action), "no second subscribed event"
  end

  test "never revives someone who opted out here, and still answers 1" do
    subscriber = Current.with_account(@account) { Subscriber.opt_in(email_address: "reader@example.com") }
    subscriber.confirm!
    subscriber.unsubscribe!

    post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: @account.slug }

    assert_equal "1", response.body, "an error would only make BookFunnel retry"
    assert subscriber.reload.unsubscribed?
  end

  test "never revives a complained or bounced address" do
    %w[complained bounced].each_with_index do |state, index|
      email = "reader#{index}@example.com"
      subscriber = Current.with_account(@account) { Subscriber.opt_in(email_address: email) }
      subscriber.public_send(state == "complained" ? :mark_complained! : :mark_bounced!)

      post subscribe_path, params: { api_key: @key, email: email, list: @account.slug }

      assert_equal "1", response.body
      assert_equal state, subscriber.reload.status
    end
  end

  test "sends no confirmation email — the consent already happened at BookFunnel" do
    assert_no_enqueued_emails do
      post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: @account.slug }
    end
  end

  test "resolves the list against the account handle too" do
    @account.update!(handle: "merovex")

    post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: "Merovex" }

    assert_equal "1", response.body
    assert_equal 1, @account.subscribers.count
  end

  test "rejects a wrong api key" do
    assert_no_difference -> { Subscriber.count } do
      post subscribe_path, params: { api_key: "wrong", email: "reader@example.com", list: @account.slug }
    end

    assert_response :success
    assert_equal "Invalid API key", response.body
  end

  test "rejects a missing api key with Sendy's own wording" do
    post subscribe_path, params: { email: "reader@example.com", list: @account.slug }

    assert_equal "API key not passed", response.body
  end

  test "an account that never opened the tab has no key to present" do
    other = Account.create!(name: "Second Press", owner: users(:bob))
    assert_nil other.sendy_api_key, "a key is minted on demand, not at creation"

    post subscribe_path, params: { api_key: "", email: "reader@example.com", list: other.slug }
    assert_equal "API key not passed", response.body, "blank must never match a NULL key"

    post subscribe_path, params: { api_key: "anything", email: "reader@example.com", list: other.slug }
    assert_equal "Invalid API key", response.body
  end

  # The reason the key is per account: it, and not the list field, decides
  # whose list a push joins. The list field is a value the caller types.
  test "one site's key cannot write to another site's list" do
    other = Account.create!(name: "Second Press", owner: users(:bob))
    other.sendy_api_key!

    assert_no_difference -> { Subscriber.count } do
      post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: other.slug }
    end

    assert_equal "Invalid list ID.", response.body
    assert_empty Current.with_account(other) { other.subscribers }
  end

  test "each account gets its own key, and rotating retires the old one" do
    other = Account.create!(name: "Second Press", owner: users(:bob))
    assert_not_equal @key, other.sendy_api_key!

    was = @key
    @account.rotate_sendy_api_key!

    post subscribe_path, params: { api_key: was, email: "reader@example.com", list: @account.slug }
    assert_equal "Invalid API key", response.body

    post subscribe_path, params: { api_key: @account.sendy_api_key, email: "reader@example.com", list: @account.slug }
    assert_equal "1", response.body
  end

  test "reports a missing email and a missing list" do
    post subscribe_path, params: { api_key: @key, list: @account.slug }
    assert_equal "Some fields are missing.", response.body

    post subscribe_path, params: { api_key: @key, email: "reader@example.com" }
    assert_equal "Some fields are missing.", response.body
  end

  test "reports an unknown list id" do
    assert_no_difference -> { Subscriber.count } do
      post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: "nobodys-list" }
    end

    assert_equal "Invalid list ID.", response.body
  end

  test "reports an address our hygiene ladder refuses" do
    assert_no_difference -> { Subscriber.count } do
      post subscribe_path, params: { api_key: @key, email: "not-an-email", list: @account.slug }
    end

    assert_equal "Invalid email address.", response.body
  end

  # Every other test here posts without a CSRF token; this one pins the other
  # half of "machine endpoint": no session is opened for a caller that has no
  # browser to carry one. (Ahoy's Rack middleware still mints its visitor
  # cookies, as it does on the webhook endpoints — BookFunnel discards them,
  # and server_side_visits is off, so no visit is recorded either way.)
  test "takes no session and needs no CSRF token" do
    post subscribe_path, params: { api_key: @key, email: "reader@example.com", list: @account.slug }

    assert_response :success
    assert_empty session.to_hash
  end
end
