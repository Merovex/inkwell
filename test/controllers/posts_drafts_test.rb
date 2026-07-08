require "test_helper"

class PostsDraftsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "the index shows only published posts, with a drafts-only link" do
    get admin_posts_path
    assert_response :success
    assert_select ".list__title", text: posts(:kickoff).title
    assert_select ".list__title", text: posts(:typography).title, count: 0
    assert_select "a[href=?]", admin_drafts_path, text: "Edit your 1 draft…"
    # List views carry no context menu — that's for individual records.
    assert_select ".canvas__head button[popovertarget]", count: 0
  end

  test "scheduled-only wording" do
    schedule records(:typography)

    get admin_posts_path
    assert_select "a[href=?]", admin_drafts_path, text: "Edit your 1 scheduled post"
  end

  test "combined wording when both exist" do
    schedule records(:typography)
    post admin_posts_path, params: { post: { title: "Another draft" } }
    post admin_posts_path, params: { post: { title: "Third draft" } }

    get admin_posts_path
    assert_select "a[href=?]", admin_drafts_path, text: "Edit your 1 scheduled post and 2 drafts…"
  end

  test "no link when everything is published" do
    records(:typography).recordable.publish

    get admin_posts_path
    assert_select "a[href=?]", admin_drafts_path, count: 0
  end

  test "the drafts page lists drafts and scheduled posts, not published ones" do
    schedule records(:typography)
    post admin_posts_path, params: { post: { title: "Fresh draft" } }

    get admin_drafts_path
    assert_response :success
    assert_select ".list__title", text: "Fresh draft"
    assert_select ".list__meta", text: /Scheduled/
    assert_select ".list__title", text: posts(:kickoff).title, count: 0
    # Rows link straight into the composer.
    assert_select "a.list__body[href=?]", edit_admin_post_path(records(:typography))
    # The scheduled row carries the "Posts on <time>" clock flag.
    tomorrow_nine = Time.zone.local(Date.tomorrow.year, Date.tomorrow.month, Date.tomorrow.day, 9)
    assert_select ".list__flag", count: 1 do
      assert_select "time[datetime=?]", tomorrow_nine.iso8601
    end
    assert_select ".list__flag", text: /Posts on/
  end

  test "rows carry a trashcan; tossing a never-published draft destroys it outright" do
    get admin_drafts_path
    assert_select ".list__action button[aria-label=Delete]"

    assert_difference "Record.count", -1 do
      assert_difference "Post.count", -1 do
        delete admin_draft_path(records(:typography))
      end
    end
    assert_redirected_to admin_drafts_path
  end

  test "tossing a reverted once-published draft trashes it on the two-year clock" do
    record = records(:kickoff)
    record.recordable.unpublish

    assert_no_difference "Record.count" do
      delete admin_draft_path(record)
    end
    assert record.reload.trashed?
    assert_in_delta 2.years.from_now.to_i, record.purge_after.to_i, 60
  end

  test "trashing a never-published draft sets the 30-day clock" do
    records(:typography).trash
    assert_in_delta 30.days.from_now.to_i, records(:typography).reload.purge_after.to_i, 60
  end

  test "trashing a published post sets the two-year clock; restore clears it" do
    record = records(:kickoff)
    record.trash
    assert_in_delta 2.years.from_now.to_i, record.reload.purge_after.to_i, 60

    record.restore
    assert_nil record.reload.purge_after
  end

  test "the purge job incinerates only overdue trash" do
    overdue = records(:typography)
    overdue.trash
    held = records(:kickoff)
    held.trash # ever-published: two-year clock

    travel_to 31.days.from_now do
      Record::PurgeTrashJob.perform_now
    end

    assert_not Record.exists?(overdue.id)
    assert Record.exists?(held.id)
  end

  private
    def schedule(record)
      patch admin_post_path(record), params: {
        post: { title: record.recordable.title },
        scheduled_posting: "true",
        scheduled_posting_at_date: Date.tomorrow.iso8601,
        scheduled_posting_at_hour: "9"
      }
    end
end
