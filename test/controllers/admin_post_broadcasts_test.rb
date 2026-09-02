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

  test "a scheduled post's banner leads with the go-live time and a keyed preview" do
    sign_in_as users(:admin)
    record = records(:typography)
    record.revise(event: :scheduled, status: :scheduled, creator: users(:alice), published_at: 1.week.from_now)
    record.reload

    get admin_post_path(record)
    assert_select ".post-banner--scheduled", text: /Goes live/
    # The preview link rides the site's own address (merovex fixture: domain
    # merovex.press) and carries the HMAC key so it resolves before publish.
    assert_select ".post-banner a[href=?]", "https://merovex.press/posts/#{record.to_slug}", text: "Preview"
    assert_match(/-#{record.preview_key}\b/, record.to_slug)
    # Reschedule (the picker) and Unschedule (revert to draft) both present.
    assert_select "button", text: /Reschedule/
    assert_select "input[type=submit][value=?]", "Unschedule"
  end

  test "the email nudge shows a cancel control for a scheduled send" do
    sign_in_as users(:admin)
    records(:kickoff).create_broadcast!(scheduled_at: 1.week.from_now)

    get admin_post_path(records(:kickoff))
    assert_select ".post-banner", text: /Scheduled to email/
    assert_select "button", text: "Cancel scheduled email"
  end

  test "a published post offers Copy link and Email it, then drops the nudge once sent" do
    sign_in_as users(:admin)

    get admin_post_path(records(:kickoff))
    assert_select "form[action=?]", admin_post_broadcast_path(records(:kickoff))   # Email it
    assert_select ".post-banner__permalink", text: /merovex\.press/               # Live at …

    records(:kickoff).create_broadcast!.update!(sent_at: Time.current, recipients_count: 5)
    get admin_post_path(records(:kickoff))
    # The email nudge is gone; the live-at link stays; the sent fact moves to the
    # status line ("Emailed to 5 subscribers on …").
    assert_select "form[action='#{admin_post_broadcast_path(records(:kickoff))}']", count: 0
    assert_select ".post-banner__permalink", text: /merovex\.press/
    assert_select ".perma-header__content", text: /Emailed to 5 subscribers/
  end
end
