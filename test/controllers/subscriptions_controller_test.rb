require "test_helper"

# The public newsletter opt-in flow: anonymous, double opt-in, token-based
# confirm/unsubscribe. Opting in persists a pending row and emails the
# confirmation link (ADR 0011).
class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  test "the signup page carries the newsletter page's invitation above the form" do
    accounts(:merovex).page("newsletter").record
      .save_edit(content: "<p>Cover reveals, once a month.</p>", creator: users(:alice))

    get newsletter_path
    assert_response :success
    assert_select ".press-body", text: /Cover reveals/
  end

  test "the subscribe page renders the form" do
    get newsletter_path
    assert_response :success
    assert_select "form[action=?]", newsletter_path
    assert_select "input[name=email_address]"
  end

  test "opting in creates a pending subscriber and emails the confirmation link" do
    assert_difference -> { Subscriber.count }, 1 do
      assert_enqueued_emails 1 do
        post newsletter_path, params: { email_address: "reader@example.com", source: "hero" }
      end
    end
    assert_redirected_to newsletter_sent_path

    subscriber = Subscriber.find_by(email_address: "reader@example.com")
    assert subscriber.pending?
    assert_equal "hero", subscriber.source
  end

  test "a disposable address lands on the vague rejected page — no subscriber, no email" do
    assert_no_difference -> { Subscriber.count } do
      assert_enqueued_emails 0 do
        post newsletter_path, params: { email_address: "burner@mailinator.com", source: "hero" }
      end
    end

    # The rejected page is its own island (no flash, no session): the static
    # site can't render either, and GET /newsletter isn't proxied.
    assert_redirected_to newsletter_rejected_path
  end

  test "the rejected page renders" do
    get newsletter_rejected_path
    assert_response :success
  end

  test "a seed inbox subscribes normally and gets its confirmation email, flagged as seed" do
    assert_difference -> { Subscriber.count }, 1 do
      assert_enqueued_emails 1 do
        post newsletter_path, params: { email_address: "daughter.park.neck@aboutmy.email", source: "newsletter_page" }
      end
    end
    assert_redirected_to newsletter_sent_path

    seed = Subscriber.find_by(email_address: "daughter.park.neck@aboutmy.email")
    assert seed.pending?
    assert seed.seed?
  end

  test "a filled honeypot is silently discarded — no subscriber, no email" do
    assert_no_difference -> { Subscriber.count } do
      assert_enqueued_emails 0 do
        post newsletter_path, params: { email_address: "bot@example.com",
          Subscriber::HONEYPOT_FIELD => "https://spam.example" }
      end
    end
    # Silently mimics a real opt-in (redirects to the same "check your email"
    # page) so the bot can't tell it was discarded.
    assert_redirected_to newsletter_sent_path
  end

  test "with Turnstile provisioned, a submit without a widget token fails closed onto the rejected page" do
    with_turnstile_secret "server-side-secret" do
      assert_no_difference -> { Subscriber.count } do
        assert_enqueued_emails 0 do
          post newsletter_path, params: { email_address: "reader@example.com" }
        end
      end
    end

    assert_redirected_to newsletter_rejected_path
  end

  test "with island auth provisioned, a request without the Worker's header is refused outright" do
    with_island_auth_secrets [ "edge-secret" ] do
      assert_no_difference -> { Subscriber.count } do
        post newsletter_path, params: { email_address: "reader@example.com" }
      end
      assert_response :forbidden
    end
  end

  test "the Worker's island-auth header opens the door — either accepted secret during a roll" do
    with_island_auth_secrets [ "current-secret", "next-secret" ] do
      post newsletter_path, params: { email_address: "reader@example.com" },
        headers: { "X-Island-Auth" => "next-secret" }
      assert_redirected_to newsletter_sent_path
    end
  end

  test "the confirmation link confirms the subscriber" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")

    get confirm_newsletter_path(token: subscriber.generate_token_for(:confirmation))
    assert_response :success
    assert subscriber.reload.confirmed?
  end

  test "the unsubscribe link unsubscribes the subscriber" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!

    get unsubscribe_newsletter_path(token: subscriber.generate_token_for(:unsubscribe))
    assert_response :success
    assert subscriber.reload.unsubscribed?
  end

  test "unsubscribing from a broadcast attributes the opt-out to that issue" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    broadcast = records(:kickoff).create_broadcast!(recipients_count: 1)
    delivery = broadcast.deliveries.create!(subscriber: subscriber, sent_at: Time.current)

    get unsubscribe_newsletter_path(token: subscriber.generate_token_for(:unsubscribe), broadcast: broadcast.id)
    assert_response :success

    assert subscriber.reload.unsubscribed?
    assert delivery.reload.unsubscribed_at, "the delivery is stamped"
    assert_equal 1, broadcast.reload.unsubscribed_count, "and the broadcast counter bumps"
  end

  test "keep re-engages a subscriber and clears a pending nudge" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    subscriber.update!(re_engagement_sent_at: 10.days.ago)

    get keep_newsletter_path(token: subscriber.generate_token_for(:unsubscribe))
    assert_response :success

    assert subscriber.reload.last_engaged_at, "engagement clock reset"
    assert_nil subscriber.re_engagement_sent_at, "pending nudge cleared"
  end

  test "a bogus token renders not found" do
    get confirm_newsletter_path(token: "nonsense")
    assert_response :not_found
  end

  private
    def with_island_auth_secrets(secrets)
      original = Rails.configuration.x.island_auth_secrets
      Rails.configuration.x.island_auth_secrets = secrets
      yield
    ensure
      Rails.configuration.x.island_auth_secrets = original
    end

    def with_turnstile_secret(secret)
      original = Rails.configuration.x.turnstile_secret_key
      Rails.configuration.x.turnstile_secret_key = secret
      yield
    ensure
      Rails.configuration.x.turnstile_secret_key = original
    end
end
