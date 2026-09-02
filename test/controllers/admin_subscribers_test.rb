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

  test "a subscriber's detail shows lifecycle and engagement in the modal" do
    sign_in_as users(:admin)
    sub = Subscriber.opt_in(email_address: "reader@example.com", source: "nav")
    sub.confirm!

    get admin_subscriber_path(sub)
    assert_response :success
    assert_select "turbo-frame#modal .modal__title", text: "reader@example.com"
    assert_select ".facts dt", text: "Status"
    assert_select ".facts dt", text: "Confirmed"
    assert_select ".facts", text: /Received/
  end

  test "the roster shows one state at a time, defaulting to confirmed, with tabs to the others" do
    Subscriber.opt_in(email_address: "pending@example.com")
    Subscriber.opt_in(email_address: "done@example.com").confirm!
    sign_in_as users(:admin)

    # Default view is confirmed only. Each row carries the full address and a
    # masked twin (cat•••@…); the "Mask addresses" toggle swaps them in CSS.
    get admin_subscribers_path
    assert_response :success
    assert_select ".subscriber-address__full", text: "done@example.com"
    assert_select ".subscriber-address__masked", text: "don•••@example.com"
    assert_select "#mask-addresses"   # the screenshot-mask toggle
    assert_select ".subscriber-address__full", text: "pending@example.com", count: 0
    assert_select "a[href=?]", admin_subscribers_path(state: "pending")
    assert_select "a[href=?]", admin_subscribers_path(state: "unsubscribed")

    # The pending tab shows only pending.
    get admin_subscribers_path(state: "pending")
    assert_select ".subscriber-address__full", text: "pending@example.com"
    assert_select ".subscriber-address__full", text: "done@example.com", count: 0
  end

  test "the roster table lists a state's rows with their join date" do
    subscriber = Subscriber.opt_in(email_address: "gone@example.com")
    subscriber.confirm!
    subscriber.update_column(:created_at, 2.weeks.ago)
    subscriber.mark_bounced!(source: "postmark")
    sign_in_as users(:admin)

    get admin_subscribers_path(state: "bounced")
    assert_select ".table .subscriber-address__full", text: "gone@example.com"
    assert_select ".table td", text: 2.weeks.ago.strftime("%b %-d")   # Joined column
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

  test "the admin can flag and unflag a deliverability seed by hand" do
    # A rotating-domain seed service (GlockApps-style) that no static list catches.
    subscriber = Subscriber.opt_in(email_address: "seed-x9@rotating-glock.example.com")
    subscriber.confirm!
    sign_in_as users(:admin)

    post admin_subscriber_seed_path(subscriber)
    assert_redirected_to admin_subscribers_path(state: "confirmed")
    assert subscriber.reload.seed?

    delete admin_subscriber_seed_path(subscriber)
    assert_not subscriber.reload.seed?
  end

  test "seeds are badged in the roster and excluded from the tab counts" do
    Subscriber.opt_in(email_address: "reader@example.com").confirm!
    Subscriber.opt_in(email_address: "report@aboutmy.email").confirm!
    sign_in_as users(:admin)

    get admin_subscribers_path
    assert_select ".subscriber-address__full", text: "report@aboutmy.email"
    assert_select ".badge", text: "Seed"
    # Count reflects real readers only: 1, not 2.
    assert_select "a[aria-current=page]", text: /Confirmed\s*\(1\)/
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
