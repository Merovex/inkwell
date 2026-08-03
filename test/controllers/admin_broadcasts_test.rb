require "test_helper"

# The broadcasts dashboard: domain-admin only, read-only send analytics.
class AdminBroadcastsTest < ActionDispatch::IntegrationTest
  test "the dashboard is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_broadcasts_path
    assert_response :not_found
  end

  test "the dashboard lists broadcasts with their metrics" do
    records(:kickoff).create_broadcast!(sent_at: Time.current,
      recipients_count: 10, delivered_count: 9, opened_count: 6, clicked_count: 3)
    sign_in_as users(:admin)

    get admin_broadcasts_path
    assert_response :success
    assert_select ".table td .u-text-strong", text: posts(:kickoff).title
    assert_match "67%", response.body  # open rate 6/9 ≈ 67%
  end

  # A post can be emailed before its publish time arrives (broadcast early, on
  # purpose). It must still show on the broadcasts dashboard like any other
  # send, and still count as scheduled on the posts index.
  test "a scheduled post broadcast early appears on the dashboard and stays scheduled" do
    records(:typography).recordable.schedule(at: 1.day.from_now, creator: users(:admin))
    records(:typography).create_broadcast!(sent_at: Time.current, recipients_count: 5)
    sign_in_as users(:admin)

    get admin_broadcasts_path
    assert_response :success
    assert_select ".table td .u-text-strong", text: records(:typography).recordable.title

    get admin_posts_path
    assert_select "a[href=?]", admin_drafts_path, text: "Edit your 1 scheduled post"
  end

  test "the dashboard shows an empty state with no broadcasts" do
    sign_in_as users(:admin)

    get admin_broadcasts_path
    assert_response :success
    assert_select ".empty__title", text: "No broadcasts yet"
  end
end
