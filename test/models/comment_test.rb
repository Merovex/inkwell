require "test_helper"

class CommentTest < ActiveSupport::TestCase
  test "originating parents the comment's record to the commented record" do
    comment = Comment.new(content: "<p>Count me in.</p>", creator: users(:alice))
    record = Record.originate(comment, parent: records(:kickoff))

    assert_equal records(:kickoff), record.parent
    assert_includes records(:kickoff).comments, comment
  end

  test "content requires presence" do
    comment = Comment.new(creator: users(:alice))

    assert_not comment.valid?
    assert comment.errors[:content].any?
  end

  test "never mutable: every edit lands as a tracked version" do
    record = records(:kickoff_comment)

    updated = record.save_edit(content: "<p>Revised.</p>")

    assert updated.persisted?
    assert_not_equal comments(:kickoff_comment).id, updated.id
    assert updated.event_updated?
    assert_equal 2, record.versions.count
    assert_equal "Revised.", record.recordable.content.to_plain_text
  end

  test "trash and restore carry the rich text forward" do
    record = records(:kickoff_comment)
    original = comments(:kickoff_comment).content.to_plain_text

    record.trash
    assert record.trashed?
    assert_equal original, record.recordable.content.to_plain_text

    record.restore
    assert_equal original, record.recordable.content.to_plain_text
  end

  test "trashed comments drop out of the parent's thread" do
    assert_includes records(:kickoff).comments, comments(:kickoff_comment)

    records(:kickoff_comment).trash

    assert_empty records(:kickoff).comments
  end
end
