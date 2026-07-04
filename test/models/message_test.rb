require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "messages share the publishable regime: publish stamps once, unpublish returns to mutable" do
    record = records(:roadmap)
    assert_nil record.recordable.published_at

    published = record.recordable.publish
    assert published.published?
    original = published.published_at

    drafted = record.recordable.unpublish
    assert drafted.drafted?
    assert record.reload.recordable.mutable?

    republished = travel_to(1.day.from_now) { record.recordable.publish }
    assert_equal original.to_i, republished.published_at.to_i, "republish preserves the original date"
  end

  test "the category carries across versions and can change on one" do
    record = records(:welcome)
    assert_equal categories(:announcement), record.recordable.category

    renamed = record.revise(event: :updated, title: "Welcome, all")
    assert_equal categories(:announcement), renamed.category, "category carries forward untouched"

    recategorized = record.revise(event: :updated, category_id: categories(:question).id)
    assert_equal categories(:question), recategorized.category
    assert_equal categories(:announcement), record.versions.first.category, "history keeps the old category"
  end

  test "a category is optional" do
    message = Message.new(title: "Uncategorized", content: "<p>hi</p>", creator: users(:alice))
    assert message.valid?
  end

  test "feed orders pinned messages first, then newest by publish date" do
    pinned = messages(:roadmap)
    pinned.update!(pinned_at: Time.current)

    assert_equal [ pinned, messages(:welcome) ], Message.feed_ordered.to_a
  end
end
