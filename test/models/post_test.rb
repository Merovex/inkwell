require "test_helper"

class PostTest < ActiveSupport::TestCase
  test "publish stamps published_at on first publish only, across versions" do
    record = records(:typography)
    assert_nil record.recordable.published_at

    published = record.recordable.publish
    assert published.published?
    original = published.published_at

    drafted = record.recordable.unpublish
    assert drafted.drafted?
    assert_equal original.to_i, drafted.published_at.to_i, "unpublish keeps the publish date"

    republished = travel_to(1.day.from_now) { record.recordable.publish }
    assert_equal original.to_i, republished.published_at.to_i, "republish preserves the original date"
  end

  test "the unpublish round trip returns the draft to mutable mode" do
    record = records(:kickoff)
    record.recordable.unpublish
    record.reload

    assert record.recordable.mutable?
    assert_no_difference "Post.count" do
      record.save_edit(creator: users(:alice), title: "Quietly reworked")
    end
  end

  test "pin and unpin are event versions" do
    record = records(:kickoff)

    pinned = record.recordable.pin
    assert pinned.event_pinned?
    assert pinned.pinned_at.present?

    unpinned = record.recordable.unpin
    assert unpinned.event_unpinned?
    assert_nil unpinned.pinned_at
  end

  test "feed orders pinned posts first, then newest by publish date" do
    pinned = posts(:typography)
    pinned.update!(pinned_at: Time.current)

    assert_equal [ pinned, posts(:kickoff) ], Post.feed_ordered.to_a
  end

  test "summary uses the author's excerpt when present" do
    post = posts(:kickoff)
    post.update!(excerpt: "A hand-written, SEO-friendly summary.")

    assert_equal "A hand-written, SEO-friendly summary.", post.summary
  end

  test "summary falls back to a truncation of the body when the excerpt is blank" do
    post = posts(:kickoff)
    assert post.excerpt.blank?

    assert_equal post.content.to_plain_text.to_s.truncate(300), post.summary
    assert_operator post.summary(length: 20).length, :<=, 20
  end
end
