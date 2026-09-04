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
    assert_match "of 10", response.body   # delivered "9 of 10"
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

  test "a broadcast's detail shows the stats and who received it" do
    broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current,
      recipients_count: 2, delivered_count: 2, opened_count: 1, clicked_count: 1)
    clicker = Subscriber.opt_in(email_address: "reader@example.com").tap(&:confirm!)
    quiet   = Subscriber.opt_in(email_address: "quiet@example.com").tap(&:confirm!)
    broadcast.deliveries.create!(subscriber: clicker, sent_at: Time.current,
      delivered_at: Time.current, opened_at: Time.current, clicked_at: Time.current)
    broadcast.deliveries.create!(subscriber: quiet, sent_at: Time.current, delivered_at: Time.current)
    sign_in_as users(:admin)

    get admin_broadcast_path(broadcast)
    assert_response :success
    # Full addresses (the mock's design), each with its outcome.
    assert_select ".recipients__who", text: "reader@example.com"
    assert_select ".recipients__who", text: "quiet@example.com"
    assert_select ".recipients__engagement--clicked", text: /Clicked/
  end

  # The regression that hid a months-long event-pipe outage: the status column
  # fell through to "Delivered" for anything that hadn't bounced or complained,
  # so a send with no delivery events back read as eight happy Delivereds next
  # to a "0 delivered of 8" counter. Unconfirmed must say so.
  test "a recipient with no delivery event reads Sent, never Delivered" do
    broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 1)
    unconfirmed = Subscriber.opt_in(email_address: "silent@example.com").tap(&:confirm!)
    broadcast.deliveries.create!(subscriber: unconfirmed, sent_at: Time.current)
    sign_in_as users(:admin)

    get admin_broadcast_path(broadcast)
    assert_response :success
    assert_select ".recipients__status", text: /Sent/
    assert_select ".recipients__status", text: /Delivered/, count: 0
  end

  test "the dashboard surfaces a send's hard bounce under the post" do
    broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 1)
    reader = Subscriber.opt_in(email_address: "reader@example.com").tap(&:confirm!)
    broadcast.deliveries.create!(subscriber: reader, sent_at: Time.current, bounced_at: Time.current)
    sign_in_as users(:admin)

    get admin_broadcasts_path
    assert_response :success
    assert_select ".broadcast-row__trouble", text: /1 hard bounce/
  end
end
