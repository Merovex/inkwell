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

  test "a broadcast's detail shows the tiles, recipient milestones, and clicked links" do
    broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current,
      recipients_count: 2, delivered_count: 2, opened_count: 1, clicked_count: 1)
    opened  = Subscriber.opt_in(email_address: "reader@example.com").tap(&:confirm!)
    ignored = Subscriber.opt_in(email_address: "quiet@example.com").tap(&:confirm!)
    delivery = broadcast.deliveries.create!(subscriber: opened, sent_at: Time.current,
      delivered_at: Time.current, opened_at: Time.current, clicked_at: Time.current)
    broadcast.deliveries.create!(subscriber: ignored, sent_at: Time.current, delivered_at: Time.current)
    DeliveryEvent.create!(provider: :ses, event: :clicked, provider_message_id: "m1",
      payload: { "click" => { "link" => "https://merovex.press/books" } },
      delivery: delivery, subscriber: opened, occurred_at: Time.current)
    sign_in_as users(:admin)

    get admin_broadcast_path(broadcast)
    assert_response :success
    assert_match "rea•••@example.com", response.body
    assert_select "a[href=?]", "https://merovex.press/books"
    # The quiet recipient shows delivered but no engagement badge trouble.
    assert_match "qui•••@example.com", response.body
  end

  test "the overview strip summarizes the window from delivery events" do
    broadcast = records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 1)
    reader = Subscriber.opt_in(email_address: "reader@example.com").tap(&:confirm!)
    delivery = broadcast.deliveries.create!(subscriber: reader, sent_at: Time.current)
    DeliveryEvent.create!(provider: :ses, event: :opened, provider_message_id: "m2",
      payload: {}, delivery: delivery, subscriber: reader, occurred_at: Time.current)
    DeliveryEvent.create!(provider: :ses, event: :hard_bounce, provider_message_id: "m3",
      payload: {}, delivery: delivery, subscriber: reader, occurred_at: Time.current)
    sign_in_as users(:admin)

    get admin_broadcasts_path
    assert_response :success
    assert_select "[data-controller=area-chart]"
    assert_match "1 hard bounce", response.body
  end
end
