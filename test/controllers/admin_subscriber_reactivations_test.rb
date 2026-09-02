require "test_helper"

# Lifting delivery suppressions from the roster: bounced returns to confirmed
# outright; complained is only re-invited via a fresh double opt-in;
# unsubscribed has no admin-side undo (docs/email-architecture.md).
class AdminSubscriberReactivationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "a bounced subscriber reactivates straight to confirmed" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com").tap(&:confirm!)
    subscriber.mark_bounced!
    sign_in_as users(:admin)

    assert_no_enqueued_emails do
      post admin_subscriber_reactivation_path(subscriber)
    end
    assert_redirected_to admin_subscribers_path(state: "confirmed")
    assert subscriber.reload.confirmed?
  end

  test "a complained subscriber is re-invited via a fresh opt-in, never silently restored" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com").tap(&:confirm!)
    subscriber.mark_complained!
    sign_in_as users(:admin)

    assert_enqueued_emails 1 do
      post admin_subscriber_reactivation_path(subscriber)
    end
    assert subscriber.reload.pending?
  end

  test "an unsubscribed subscriber has no reactivation" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com").tap(&:confirm!)
    subscriber.unsubscribe!
    sign_in_as users(:admin)

    post admin_subscriber_reactivation_path(subscriber)
    assert subscriber.reload.unsubscribed?
    follow_redirect!
    assert_match "be reactivated from unsubscribed", response.body
  end
end
