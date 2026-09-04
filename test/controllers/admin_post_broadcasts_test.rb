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

  test "scheduling via the day/hour picker defers the send to half past" do
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
    assert_equal Time.utc(date.year, date.month, date.day, 9, 30), broadcast.scheduled_at,
      "an email books at half past, so it can't beat a post published on the hour"
  end

  test "an email can't be booked before its post publishes" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    publish_at = 1.week.from_now.change(hour: 9, min: 0)
    record.recordable.schedule(at: publish_at)

    assert_no_difference -> { Broadcast.count } do
      post admin_post_broadcast_path(record), params: {
        scheduled_posting: "true",
        scheduled_posting_at_date: publish_at.to_date.iso8601,
        scheduled_posting_at_hour: "8",   # 8:30 — before the 9:00 publish
        scheduled_posting_at_zone: Time.zone.name
      }
    end

    assert_match "before the post publishes", flash[:alert]
  end

  test "the post's own publish hour is bookable — half past lands after it" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    publish_at = 1.week.from_now.change(hour: 9, min: 0)
    record.recordable.schedule(at: publish_at)

    post admin_post_broadcast_path(record), params: {
      scheduled_posting: "true",
      scheduled_posting_at_date: publish_at.to_date.iso8601,
      scheduled_posting_at_hour: "9",
      scheduled_posting_at_zone: Time.zone.name
    }

    broadcast = record.reload.broadcast
    assert broadcast.scheduled?
    assert_equal publish_at + 30.minutes, broadcast.scheduled_at
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

  # An email booked against a date the post no longer keeps would fire while
  # the post is still unpublished — so a transition away from that date drops
  # it, loudly.
  test "rescheduling the post clears a booked email and says so" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    publish_at = 1.week.from_now.change(hour: 9, min: 0)
    record.recordable.schedule(at: publish_at)
    record.create_broadcast!(scheduled_at: publish_at + 30.minutes)

    patch admin_post_path(record), params: {
      post: { title: record.recordable.title },
      scheduled_posting: "true",
      scheduled_posting_at_date: (publish_at + 2.days).to_date.iso8601,
      scheduled_posting_at_hour: "9",
      scheduled_posting_at_zone: Time.zone.name
    }

    assert_nil record.reload.broadcast, "the send was booked against the old date"
    assert_match "scheduled email was cleared", flash[:notice]
  end

  test "saving the scheduler without moving the date leaves the email alone" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    publish_at = 1.week.from_now.change(hour: 9, min: 0)
    record.recordable.schedule(at: publish_at)
    record.create_broadcast!(scheduled_at: publish_at + 30.minutes)

    patch admin_post_path(record), params: {
      post: { title: record.recordable.title },
      scheduled_posting: "true",
      scheduled_posting_at_date: publish_at.to_date.iso8601,
      scheduled_posting_at_hour: publish_at.hour.to_s,
      scheduled_posting_at_zone: Time.zone.name
    }

    assert record.reload.broadcast&.scheduled?, "nothing moved, so nothing should be cleared"
    assert_no_match "email was cleared", flash[:notice].to_s
  end

  test "unscheduling the post clears a booked email" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    publish_at = 1.week.from_now.change(hour: 9, min: 0)
    record.recordable.schedule(at: publish_at)
    record.create_broadcast!(scheduled_at: publish_at + 30.minutes)

    patch admin_post_path(record), params: {
      post: { title: record.recordable.title }, scheduled_posting: "false"
    }

    assert record.reload.recordable.drafted?
    assert_nil record.reload.broadcast
    assert_match "scheduled email was cleared", flash[:notice]
  end

  test "reverting a published post to a draft clears its booked email" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    record.recordable.publish
    record.create_broadcast!(scheduled_at: 2.days.from_now)

    delete admin_post_publish_path(record)

    post_now = record.reload.recordable
    assert post_now.drafted?
    assert post_now.published_at, "a published post keeps its date across a revert — see post_test"
    assert_nil record.reload.broadcast
    assert_match "scheduled email was cleared", flash[:notice]
  end

  test "an email already sent is never cleared by a later transition" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    record.recordable.publish
    sent = record.create_broadcast!(sent_at: Time.current, recipients_count: 3)

    delete admin_post_publish_path(record)

    assert_equal sent, record.reload.broadcast, "a send that happened is history"
    assert_no_match "email was cleared", flash[:notice].to_s
  end

  # The gap that made all of this invisible: the email panel only existed in
  # the published branch of the status banner, so a scheduled post — the exact
  # case you'd want to book an email for — offered no way to do it.
  test "a scheduled post offers the email picker, opened on its own publish slot" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    publish_at = 1.week.from_now.change(hour: 9, min: 0)
    record.recordable.schedule(at: publish_at)

    get admin_post_path(record)

    assert_response :success
    assert_select "#broadcast-scheduler", 1, "a scheduled post can book its email"
    assert_select "button[popovertarget=broadcast-scheduler]" do |trigger|
      assert_equal "Email subscribers", trigger.first.text.squish
      assert_nil trigger.first["aria-label"], "the visible label is the accessible name"
    end
    # Opened on the post's own day and hour — which the :30 grid books as half
    # an hour after it goes live. (A message can't ride these assertions: the
    # argument after a ? substitution is read as the expected text.)
    assert_select "#broadcast-scheduler select#scheduled_posting_at_date option[selected][value=?]",
      publish_at.to_date.iso8601
    assert_select "#broadcast-scheduler select#scheduled_posting_at_hour option[selected][value=?]",
      publish_at.hour.to_s
  end

  test "a scheduled post with a booked email offers to cancel it, not book another" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    publish_at = 1.week.from_now.change(hour: 9, min: 0)
    record.recordable.schedule(at: publish_at)
    record.create_broadcast!(scheduled_at: publish_at + 30.minutes)

    get admin_post_path(record)

    assert_select "#broadcast-scheduler", 0
    assert_select "form[action=?][method=post]", admin_post_broadcast_path(record) do
      assert_select "input[name=_method][value=delete]"
    end
  end

  test "an unpublished post can't be emailed right now, only scheduled" do
    sign_in_as users(:admin)
    record = records(:kickoff)
    record.recordable.schedule(at: 1.week.from_now.change(hour: 9, min: 0))

    assert_no_difference -> { Broadcast.count } do
      post admin_post_broadcast_path(record)   # no scheduled_posting → an immediate send
    end

    assert_match "isn't live yet", flash[:alert]
  end
end
