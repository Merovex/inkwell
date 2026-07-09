require "test_helper"

# Emailing a post to subscribers: one-time, only for a live/scheduled post,
# creator/admin only. The HEY World banner drives it from the post page.
class AdminPostBroadcastsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "broadcasting a published post creates the send and enqueues the fan-out" do
    sign_in_as users(:admin)

    assert_enqueued_with(job: PostBroadcastJob) do
      assert_difference -> { Broadcast.count }, 1 do
        post admin_post_broadcast_path(records(:kickoff))
      end
    end
    assert_redirected_to admin_post_path(records(:kickoff))
    assert records(:kickoff).reload.broadcast.present?
  end

  test "a draft cannot be broadcast" do
    sign_in_as users(:admin)

    assert_no_difference -> { Broadcast.count } do
      post admin_post_broadcast_path(records(:typography))
    end
    assert_redirected_to admin_post_path(records(:typography))
    assert_equal "Publish or schedule the post before emailing it.", flash[:alert]
  end

  test "a post cannot be broadcast twice" do
    sign_in_as users(:admin)
    records(:kickoff).create_broadcast!

    assert_no_difference -> { Broadcast.count } do
      post admin_post_broadcast_path(records(:kickoff))
    end
    assert_equal "This post has already been emailed to subscribers.", flash[:alert]
  end

  test "a non-manager cannot broadcast someone else's post" do
    sign_in_as users(:bob)

    assert_no_difference -> { Broadcast.count } do
      post admin_post_broadcast_path(records(:kickoff))
    end
    assert_response :not_found
  end

  test "scheduling via the day/hour picker defers the send" do
    sign_in_as users(:admin)
    date = 1.week.from_now.to_date

    assert_enqueued_with(job: PostBroadcastJob) do
      post admin_post_broadcast_path(records(:kickoff)), params: {
        scheduled_posting: "true",
        scheduled_posting_at_date: date.iso8601,
        scheduled_posting_at_hour: "9",
        scheduled_posting_at_zone: "UTC"
      }
    end

    broadcast = records(:kickoff).reload.broadcast
    assert broadcast.scheduled?
    assert_equal Time.utc(date.year, date.month, date.day, 9), broadcast.scheduled_at
  end

  test "a past send time is rejected" do
    sign_in_as users(:admin)
    date = 1.day.ago.to_date

    assert_no_difference -> { Broadcast.count } do
      post admin_post_broadcast_path(records(:kickoff)), params: {
        scheduled_posting: "true",
        scheduled_posting_at_date: date.iso8601,
        scheduled_posting_at_hour: "9",
        scheduled_posting_at_zone: "UTC"
      }
    end
    assert_match "already passed", flash[:alert]
  end

  test "canceling a scheduled broadcast removes it" do
    sign_in_as users(:admin)
    records(:kickoff).create_broadcast!(scheduled_at: 1.week.from_now)

    assert_difference -> { Broadcast.count }, -1 do
      delete admin_post_broadcast_path(records(:kickoff))
    end
    assert_redirected_to admin_post_path(records(:kickoff))
    assert_equal "Scheduled email canceled.", flash[:notice]
  end

  test "a sent broadcast cannot be canceled" do
    sign_in_as users(:admin)
    records(:kickoff).create_broadcast!(sent_at: Time.current, recipients_count: 3)

    assert_no_difference -> { Broadcast.count } do
      delete admin_post_broadcast_path(records(:kickoff))
    end
    assert_match "no scheduled send", flash[:alert]
  end

  test "the banner shows the keyed preview link while the post is scheduled" do
    sign_in_as users(:admin)
    record = records(:typography)
    record.revise(event: :scheduled, status: :scheduled, creator: users(:alice), published_at: 1.week.from_now)
    record.reload

    get admin_post_path(record)
    assert_select ".broadcast-banner a", text: "preview link"
    assert_select ".broadcast-banner__url[value=?]", blog_post_url(record.to_slug)
    assert_match(/-#{record.preview_key}\b/, record.to_slug)  # the URL carries the HMAC key
  end

  test "the banner shows a cancel control for a scheduled send" do
    sign_in_as users(:admin)
    records(:kickoff).create_broadcast!(scheduled_at: 1.week.from_now)

    get admin_post_path(records(:kickoff))
    assert_select ".broadcast-banner__stamp", text: /Scheduled to email/
    assert_select "button", text: "Cancel scheduled email"
  end

  test "the banner offers the email button on a published post, then shows the sent stamp" do
    sign_in_as users(:admin)

    get admin_post_path(records(:kickoff))
    assert_select "form[action=?]", admin_post_broadcast_path(records(:kickoff))
    assert_select ".broadcast-banner a", text: "live on the web"

    records(:kickoff).create_broadcast!.update!(sent_at: Time.current, recipients_count: 5)
    get admin_post_path(records(:kickoff))
    # The email button is gone, but the share link stays and a sent stamp shows.
    assert_select "form[action='#{admin_post_broadcast_path(records(:kickoff))}']", count: 0
    assert_select ".broadcast-banner a", text: "live on the web"
    assert_select ".broadcast-banner__stamp", text: /Sent to 5 subscribers/
  end
end
