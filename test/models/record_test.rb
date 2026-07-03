require "test_helper"

class RecordTest < ActiveSupport::TestCase
  test "revise inserts an immutable version and repoints the cursor" do
    record = records(:kickoff)
    v1 = record.recordable

    v2 = record.revise(event: :updated, creator: users(:alice), title: "Renamed")

    assert v2.persisted?
    assert_equal v2, record.reload.recordable
    assert_equal "Kickoff notes for the winter issue", v1.reload.title, "superseded version untouched"
    assert_equal [ v1, v2 ], record.versions.to_a
  end

  test "revise copies scalars forward and keeps the body unless content changes" do
    record = records(:kickoff)
    v1 = record.recordable

    v2 = record.revise(event: :published, creator: users(:alice))
    assert_equal v1.body_id, v2.body_id, "action-only versions share the body"
    assert_equal v1.published_at.to_i, v2.published_at.to_i

    v3 = record.revise(event: :updated, creator: users(:alice), content: "<p>Fresh text</p>")
    assert_not_equal v2.body_id, v3.body_id, "a content change mints a new body"
    assert_equal "Fresh text", v3.content.to_plain_text
    assert_equal "Pulling together the themes we landed on last week — the long-form essay, two shorter pieces, and the interview.",
      v1.content.to_plain_text, "old version keeps its own body"
  end

  test "an invalid revision leaves the cursor alone" do
    record = records(:kickoff)
    current = record.recordable

    version = record.revise(event: :updated, creator: users(:alice), title: "")

    assert_not version.persisted?
    assert version.errors[:title].any?
    assert_equal current, record.reload.recordable
  end

  test "save_edit mutates drafts in place, versions published content" do
    draft = records(:typography)
    assert_no_difference "Post.count" do
      draft.save_edit(creator: users(:alice), title: "Draft churn")
    end
    assert_equal "Draft churn", draft.recordable.reload.title

    live = records(:kickoff)
    assert_difference "Post.count", 1 do
      live.save_edit(creator: users(:alice), title: "Tracked change")
    end
    assert_equal "Tracked change", live.recordable.title
    assert live.recordable.event_updated?
  end

  test "trash is an event version plus the envelope filter, draft or published" do
    draft = records(:typography)
    assert_difference "Post.count", 1 do
      draft.trash
    end
    assert draft.trashed?
    assert draft.versions.last.event_trashed?
    assert_includes Record.trashed, draft

    draft.restore
    assert_not draft.trashed?
    assert draft.versions.last.event_restored?
  end

  test "destroying a record destroys all versions and orphaned bodies" do
    record = records(:kickoff)
    record.revise(event: :updated, creator: users(:alice), content: "<p>v2</p>")
    version_ids = record.versions.pluck(:id)
    body_ids = record.versions.pluck(:body_id).uniq
    assert_equal 2, version_ids.size

    record.destroy

    assert_empty Post.where(id: version_ids)
    assert_empty Body.where(id: body_ids)
  end

  test "children thread to their parent and are destroyed with it" do
    parent = records(:kickoff)
    child = records(:typography)
    child.update!(parent: parent)

    assert_includes parent.children, child
    parent.destroy
    assert_not Record.exists?(child.id)
  end

  test "a version can only be the cursor of one record" do
    assert_raises ActiveRecord::RecordNotUnique do
      Record.create!(recordable: records(:kickoff).recordable, creator: users(:alice))
    end
  end
end
