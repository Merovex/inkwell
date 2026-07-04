require "test_helper"

class PostsSchedulingTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as users(:alice)
    @tomorrow_nine = Time.zone.local(Date.tomorrow.year, Date.tomorrow.month, Date.tomorrow.day, 9)
  end

  test "the draft composer offers the scheduler panel with disabled controls" do
    get new_post_path
    assert_response :success
    assert_select "[popovertarget=scheduler-panel]"
    assert_select ".scheduler[popover]" do
      assert_select "select#scheduled_posting_at_date[form=composer][disabled]" do
        assert_select "option", count: 30
        assert_select "option[selected]", text: "Tomorrow"
      end
      assert_select "select#scheduled_posting_at_hour[form=composer][disabled]" do
        assert_select "option", count: 24
        assert_select "option[selected]", text: "9:00"
      end
      assert_select "input#scheduled_posting[value=false][form=composer][disabled]"
      assert_select "button[type=submit][form=composer]", text: "Schedule and save"
    end

    # A published post's composer has no scheduler.
    get edit_post_path(records(:kickoff))
    assert_select ".scheduler", count: 0
  end

  test "schedule and save creates a scheduled version and enqueues the publish job" do
    assert_enqueued_with job: Record::PublishLaterJob do
      post posts_path, params: {
        post: { title: "Later", content: "<p>soon</p>" },
        scheduled_posting: "true",
        scheduled_posting_at_date: Date.tomorrow.iso8601,
        scheduled_posting_at_hour: "9"
      }
    end

    record = Record.order(:id).last
    current = record.recordable
    assert current.scheduled?
    assert current.event_scheduled?
    assert_equal @tomorrow_nine, current.published_at
    assert_equal %w[ created scheduled ], record.versions.map(&:event)
  end

  test "a scheduled post stays mutable without events" do
    record = schedule_typography

    assert_no_difference "Post.count" do
      patch post_path(record), params: { post: { title: "Quiet rewrite" } }
    end
    assert_equal "Quiet rewrite", record.reload.recordable.title
    assert record.recordable.scheduled?
  end

  test "the publish job publishes at the appointed time, stamped with it" do
    record = schedule_typography

    travel_to @tomorrow_nine + 1.minute do
      perform_enqueued_jobs only: Record::PublishLaterJob
    end

    current = record.reload.recordable
    assert current.published?
    assert current.event_published?
    assert_equal @tomorrow_nine, current.published_at
  end

  test "the publish job is a no-op when the post was trashed meanwhile" do
    record = schedule_typography
    record.trash

    travel_to @tomorrow_nine + 1.minute do
      perform_enqueued_jobs only: Record::PublishLaterJob
    end
    assert_not record.reload.recordable.published?
  end

  test "publishing a scheduled post early stamps now, not the future date" do
    record = schedule_typography

    post post_publish_path(record)

    current = record.reload.recordable
    assert current.published?
    assert current.published_at <= Time.current
  end

  test "the appointment is interpreted in the browser's zone" do
    post posts_path, params: {
      post: { title: "Zoned", content: "<p>tz</p>" },
      scheduled_posting: "true",
      scheduled_posting_at_date: Date.tomorrow.iso8601,
      scheduled_posting_at_hour: "9",
      scheduled_posting_at_zone: "America/New_York"
    }

    eastern_nine = Time.find_zone("America/New_York")
      .local(Date.tomorrow.year, Date.tomorrow.month, Date.tomorrow.day, 9)
    assert_equal eastern_nine, Record.order(:id).last.recordable.published_at
  end

  test "scheduling a time that already passed is rejected, not insta-published" do
    assert_no_enqueued_jobs only: Record::PublishLaterJob do
      assert_no_difference "Post.count" do
        patch post_path(records(:typography)), params: {
          post: { title: "Too late" },
          scheduled_posting: "true",
          scheduled_posting_at_date: Date.current.iso8601,
          scheduled_posting_at_hour: "0"
        }
      end
    end
    assert_response :unprocessable_entity
    assert_match "already passed", response.body
  end

  test "a tampered schedule date or hour is rejected, not a 500" do
    assert_no_difference "Post.count" do
      post posts_path, params: {
        post: { title: "Garbage date", content: "<p>?</p>" },
        scheduled_posting: "true",
        scheduled_posting_at_date: "not-a-date",
        scheduled_posting_at_hour: "9"
      }
    end
    assert_response :unprocessable_entity
    assert_match "already passed", response.body

    assert_no_difference "Post.count" do
      post posts_path, params: {
        post: { title: "Garbage hour", content: "<p>?</p>" },
        scheduled_posting: "true",
        scheduled_posting_at_date: Date.tomorrow.iso8601,
        scheduled_posting_at_hour: "99"
      }
    end
    assert_response :unprocessable_entity
  end

  test "editing a scheduled post gets the reschedule composer" do
    record = schedule_typography

    get edit_post_path(record)
    assert_response :success
    # Head: clock + "Post on ..." + Never mind + Save.
    assert_select ".canvas__head time[datetime=?]", @tomorrow_nine.iso8601
    assert_select ".canvas__head a", text: "Never mind"
    assert_select ".canvas__head button[form=composer]", text: "Save"
    # Panel: appointment preselected, editing-mode buttons, flag starts true.
    assert_select ".scheduler" do
      assert_select "option[selected][value=?]", Date.tomorrow.iso8601
      assert_select "select#scheduled_posting_at_hour option[selected][value='9']"
      assert_select "button", text: "Save"
      assert_select "button[name=publish]", text: "Post now instead"
      assert_select "button", text: "unschedule and save"
      assert_select "input#scheduled_posting[value=true]"
    end
  end

  test "unschedule and save reverts to a plain draft" do
    record = schedule_typography

    patch post_path(record), params: { post: { title: "Back to draft" }, scheduled_posting: "false" }

    current = record.reload.recordable
    assert current.drafted?
    assert current.event_unscheduled?
    assert_nil current.published_at
    assert_equal "Back to draft", current.title

    get post_events_path(record)
    assert_select ".history__line", text: /unscheduled this post/
  end

  test "post now instead publishes immediately, stamped now" do
    record = schedule_typography

    patch post_path(record), params: { post: { title: "Now" }, scheduled_posting: "false", publish: "1" }

    current = record.reload.recordable
    assert current.published?
    assert current.published_at <= Time.current
  end

  test "a plain save on a scheduled post keeps the appointment, silently" do
    record = schedule_typography

    assert_no_difference "Post.count" do
      patch post_path(record), params: { post: { title: "Quiet" } }
    end
    current = record.reload.recordable
    assert current.scheduled?
    assert_equal @tomorrow_nine, current.published_at
  end

  test "the change log narrates the schedule" do
    record = schedule_typography

    get post_events_path(record)
    assert_select ".history__line", text: /scheduled this post to publish #{@tomorrow_nine.strftime('%b %-d at %H:%M')}/
  end

  private
    def schedule_typography
      records(:typography).tap do |record|
        patch post_path(record), params: {
          post: { title: "Later", content: "<p>soon</p>" },
          scheduled_posting: "true",
          scheduled_posting_at_date: Date.tomorrow.iso8601,
          scheduled_posting_at_hour: "9"
        }
        record.reload
      end
    end
end
