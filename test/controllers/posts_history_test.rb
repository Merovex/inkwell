require "test_helper"

# The full ADR 0007 scenario driven through the UI: draft churn is silent,
# published changes are tracked, the feed derives its lines from version deltas.
class PostsHistoryTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
    @record = records(:typography) # a draft
  end

  test "the six-line scenario: draft, publish, edit, revert, redraft, publish" do
    # Draft churn: three silent edits.
    3.times { |i| patch post_path(@record), params: { post: { title: "Draft #{i}", content: "<p>take #{i}</p>" } } }
    assert_equal 1, @record.versions.count

    post post_publish_path(@record)                                    # publish
    patch post_path(@record), params: { post: { title: "Draft 2", content: "<p>tightened</p>" } } # tracked edit
    delete post_publish_path(@record)                                  # revert to draft
    4.times { |i| patch post_path(@record), params: { post: { content: "<p>redraft #{i}</p>", title: "Draft 2" } } }
    post post_publish_path(@record)                                    # publish again

    assert_equal 5, @record.versions.count, "created, published, updated, unpublished, published"

    get post_events_path(@record)
    assert_response :success
    assert_select ".history__entry", count: 5
    assert_select ".history__line", text: /created this post/
    assert_select ".history__line", text: /published this post/
    assert_select ".history__line", text: /saved a new version/
    assert_select ".history__line", text: /reverted this post to a draft/
  end

  test "a title-only tracked change renders the from/to line" do
    record = records(:kickoff) # published
    patch post_path(record), params: { post: { title: "New title" } }

    get post_events_path(record)
    assert_select ".history__line", text: /changed the title of this post from “Kickoff notes for the winter issue” to “New title”/
  end

  test "See the changes links past versions that differ from current" do
    record = records(:kickoff)
    v1 = record.recordable
    patch post_path(record), params: { post: { title: posts(:kickoff).title, content: "<p>Pulling together the themes we settled on last week.</p>" } }

    get post_events_path(record)
    assert_response :success
    assert_select "a.history__action[href=?]", post_change_path(record, v1), text: "See the changes"
    # The current version never links to a self-diff.
    assert_select "a[href=?]", post_change_path(record, record.reload.recordable), count: 0
  end

  test "the change page diffs the past version against the CURRENT one, not its neighbor" do
    record = records(:kickoff)
    v1 = record.recordable
    patch post_path(record), params: { post: { title: posts(:kickoff).title, content: "<p>Pulling together the themes we settled on last week.</p>" } }
    patch post_path(record), params: { post: { title: posts(:kickoff).title, content: "<p>Pulling together the themes we settled on last month.</p>" } }

    get post_change_path(record, v1)
    assert_response :success
    # Deletions come from v1; insertions include the change made two versions later.
    assert_select ".history__diff del", text: "landed"
    assert_select ".history__diff del", text: "week"
    assert_select ".history__diff ins", text: "settled"
    assert_select ".history__diff ins", text: "month."
  end

  test "a frozen version renders read-only" do
    record = records(:kickoff)
    v1 = record.recordable
    patch post_path(record), params: { post: { title: "Renamed", content: "<p>changed</p>" } }

    get post_version_path(record, v1)
    assert_response :success
    assert_select "h1", text: "Kickoff notes for the winter issue"
    assert_select "article", text: /themes we landed on/
  end
end
