require "test_helper"

# The admin subscriber roster: domain-admin only, read + CSV export + manual
# unsubscribe. Subscribers opt in from the public site, so there's no create here.
class AdminSubscribersTest < ActionDispatch::IntegrationTest
  test "the roster is admin-only: a member gets a 404" do
    sign_in_as users(:alice)

    get admin_subscribers_path
    assert_response :not_found
  end

  test "the roster shows one state at a time, defaulting to confirmed, with tabs to the others" do
    Subscriber.opt_in(email_address: "pending@example.com")
    Subscriber.opt_in(email_address: "done@example.com").confirm!
    sign_in_as users(:admin)

    # Default view is confirmed only.
    get admin_subscribers_path
    assert_response :success
    assert_select ".list__title", text: "done@example.com"
    assert_select ".list__title", text: "pending@example.com", count: 0
    assert_select "a[href=?]", admin_subscribers_path(state: "pending")
    assert_select "a[href=?]", admin_subscribers_path(state: "unsubscribed")

    # The pending tab shows only pending.
    get admin_subscribers_path(state: "pending")
    assert_select ".list__title", text: "pending@example.com"
    assert_select ".list__title", text: "done@example.com", count: 0
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
end
