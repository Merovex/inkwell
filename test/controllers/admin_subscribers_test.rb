require "test_helper"

# The admin subscriber roster: domain-admin only, read + CSV export + manual
# unsubscribe. Subscribers opt in from the public site, so there's no create here.
class AdminSubscribersTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "the roster is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_subscribers_path
    assert_response :not_found
  end

  test "the roster shows one state at a time, defaulting to confirmed, with tabs to the others" do
    Subscriber.opt_in(email_address: "pending@example.com")
    Subscriber.opt_in(email_address: "done@example.com").confirm!
    sign_in_as users(:admin)

    # Default view is confirmed only. Addresses are shown redacted: the local
    # part is cut to three letters + a mask, and the full form never appears.
    get admin_subscribers_path
    assert_response :success
    assert_select ".list__title", text: "don•••@example.com"
    assert_not_includes response.body, "done@example.com"
    assert_select ".list__title", text: "pen•••@example.com", count: 0
    assert_select "a[href=?]", admin_subscribers_path(state: "pending")
    assert_select "a[href=?]", admin_subscribers_path(state: "unsubscribed")

    # The pending tab shows only pending.
    get admin_subscribers_path(state: "pending")
    assert_select ".list__title", text: "pen•••@example.com"
    assert_select ".list__title", text: "don•••@example.com", count: 0
  end

  test "the byline shows updated_at when the row changed after joining" do
    subscriber = Subscriber.opt_in(email_address: "gone@example.com")
    subscriber.confirm!
    subscriber.update_column(:created_at, 2.weeks.ago)  # joined earlier; bounce touches updated_at today
    subscriber.mark_bounced!(source: "postmark")
    sign_in_as users(:admin)

    get admin_subscribers_path(state: "bounced")
    assert_select ".list__byline", text: /updated #{Time.current.strftime("%b %-d, %Y")}/
  end

  test "export gives the current state as CSV" do
    Subscriber.opt_in(email_address: "reader@example.com", source: "hero").confirm!
    sign_in_as users(:admin)

    get admin_subscribers_path(format: :csv)  # defaults to confirmed
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "reader@example.com"
    assert_includes response.body, "email_address,status,source"
  end

  test "the admin can unsubscribe someone manually" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    sign_in_as users(:admin)

    patch unsubscribe_admin_subscriber_path(subscriber)
    assert_redirected_to admin_subscribers_path
    assert subscriber.reload.unsubscribed?
    assert_equal "admin", subscriber.events.last.source
  end

  test "the admin can resend the confirmation email to a pending subscriber" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")  # pending
    sign_in_as users(:admin)

    assert_enqueued_emails 1 do
      post resend_admin_subscriber_path(subscriber)
    end
    assert_redirected_to admin_subscribers_path(state: "pending")
    assert subscriber.reload.pending?
  end

  test "resending to an already-confirmed subscriber is a no-op with a heads-up" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    subscriber.confirm!
    sign_in_as users(:admin)

    assert_enqueued_emails 0 do
      post resend_admin_subscriber_path(subscriber)
    end
    assert_redirected_to admin_subscribers_path(state: "confirmed")
    assert_equal "reader@example.com isn't pending — nothing to confirm.", flash[:alert]
  end

  test "resend is admin-only: a member gets a 404" do
    subscriber = Subscriber.opt_in(email_address: "reader@example.com")
    sign_in_as users(:bob)

    assert_enqueued_emails 0 do
      post resend_admin_subscriber_path(subscriber)
    end
    assert_response :not_found
  end
end
