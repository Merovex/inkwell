require "test_helper"

# The public newsletter opt-in flow: anonymous, double opt-in, token-based
# confirm/unsubscribe. Opting in persists a pending row and emails the
# confirmation link (ADR 0011).
class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
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
    assert_redirected_to newsletter_path

    subscriber = Subscriber.find_by(email_address: "reader@example.com")
    assert subscriber.pending?
    assert_equal "hero", subscriber.source
  end

  test "a filled honeypot is silently discarded — no subscriber, no email" do
    assert_no_difference -> { Subscriber.count } do
      assert_enqueued_emails 0 do
        post newsletter_path, params: { email_address: "bot@example.com",
          InvisibleCaptcha.honeypots.first => "i am a bot" }
      end
    end
    assert_redirected_to newsletter_path
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

  test "a bogus token renders not found" do
    get confirm_newsletter_path(token: "nonsense")
    assert_response :not_found
  end
end
