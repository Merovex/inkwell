require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "index lists active posts, linked by record id" do
    get admin_posts_path
    assert_response :success
    assert_select ".list__title", text: posts(:kickoff).title
    assert_select "a.list__body[href=?]", admin_post_path(records(:kickoff))
  end

  test "index hides trashed posts" do
    records(:kickoff).trash

    get admin_posts_path
    assert_select ".list__title", text: posts(:kickoff).title, count: 0
  end

  test "show is keyed by the record id and renders the current version" do
    get admin_post_path(records(:kickoff))
    assert_response :success
    assert_select "h1", text: posts(:kickoff).title
    assert_select ".lexxy-content", text: /themes we landed on/
  end

  test "trashed posts are not found" do
    records(:kickoff).trash

    get admin_post_path(records(:kickoff))
    assert_response :not_found
  end

  test "new and edit render the composer: Lexxy body, head buttons, no visible labels" do
    get new_admin_post_path
    assert_response :success
    assert_select "lexxy-editor"
    # Save draft + Publish + the scheduler's Schedule and save.
    assert_select ".canvas__head button[form=composer]", count: 3
    assert_select "label", false

    # Editing a published post: Update + Never mind, no publish controls.
    get edit_admin_post_path(records(:kickoff))
    assert_response :success
    assert_select "lexxy-editor"
    assert_select ".canvas__head button[form=composer]", text: "Update", count: 1
    assert_select ".canvas__head a", text: "Never mind"

    # Editing a draft keeps Save draft + Publish (+ the scheduler's submit).
    get edit_admin_post_path(records(:typography))
    assert_select ".canvas__head button[form=composer]", count: 3
  end

  test "composer autosaves: new posts share one draft slot, edits key to the record" do
    get new_admin_post_path
    assert_select "form#composer[data-controller=autosave][data-autosave-key-value=?]", "posts/new"

    get edit_admin_post_path(records(:kickoff))
    assert_select "form#composer[data-autosave-key-value=?]", "Record/#{records(:kickoff).id}/edit"
    # The revision guard is the record's current version id.
    assert_select "form#composer[data-autosave-revision-value=?]", posts(:kickoff).id.to_s
  end

  test "create as draft wraps the post in a record" do
    assert_difference [ "Post.count", "Record.count" ], 1 do
      post admin_posts_path, params: { post: { title: "Hello spine", content: "<p>Hi</p>" } }
    end

    created = Record.order(:id).last
    assert_redirected_to admin_post_path(created)
    assert created.recordable.drafted?
    assert created.recordable.event_created?
    assert_equal users(:alice), created.recordable.creator
  end

  test "create with the Publish button publishes immediately" do
    post admin_posts_path, params: { post: { title: "Hot take", content: "<p>!</p>" }, publish: "1" }
    assert Record.order(:id).last.recordable.published?
  end

  test "create with a blank title re-renders the form and makes no rows" do
    assert_no_difference [ "Post.count", "Record.count" ] do
      post admin_posts_path, params: { post: { title: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "editing a draft mutates in place" do
    assert_no_difference "Post.count" do
      patch admin_post_path(records(:typography)), params: { post: { title: "Still a draft" } }
    end
    assert_equal "Still a draft", posts(:typography).reload.title
  end

  test "editing a published post inserts a tracked version" do
    assert_difference "Post.count", 1 do
      patch admin_post_path(records(:kickoff)), params: { post: { title: "Renamed live" } }
    end
    assert_equal "Renamed live", records(:kickoff).reload.recordable.title
    assert_equal "Kickoff notes for the winter issue", posts(:kickoff).reload.title
  end

  test "publishing a draft from the composer folds edits into the published version" do
    patch admin_post_path(records(:typography)),
      params: { post: { title: "Ready now", content: "<p>Final</p>" }, publish: "1" }

    current = records(:typography).reload.recordable
    assert current.published?
    assert current.event_published?
    assert_equal "Ready now", current.title
  end

  test "destroy trashes the record, writing the event version" do
    assert_difference "Post.count", 1 do
      delete admin_post_path(records(:kickoff))
    end
    assert records(:kickoff).reload.trashed?
    assert records(:kickoff).versions.last.event_trashed?
    assert_redirected_to admin_posts_path
  end

  test "publish then revert keeps the original publish date" do
    record = records(:typography)

    post admin_post_publish_path(record)
    assert record.reload.recordable.published?
    first_published_at = record.recordable.published_at

    delete admin_post_publish_path(record)
    assert record.reload.recordable.drafted?
    assert_equal first_published_at.to_i, record.recordable.published_at.to_i
  end

  test "pin and unpin via the resource" do
    record = records(:kickoff)

    post admin_post_pin_path(record)
    assert record.reload.recordable.pinned_at.present?

    delete admin_post_pin_path(record)
    assert_nil record.reload.recordable.pinned_at
  end

  test "pinned posts are flagged and sort to the top of the index" do
    late = Record.originate(Post.new(title: "Newer post", event: :created,
      status: :published, published_at: Time.current, creator: users(:alice)))
    records(:kickoff).recordable.pin

    get admin_posts_path
    assert_select ".list__flag", text: /Pinned/, count: 1
    assert_select ".list__item:first-child .list__title", text: posts(:kickoff).title
    assert_select ".list__item:first-child .list__flag", text: /Pinned/
    assert late.recordable.published?
  end

  test "requires authentication" do
    delete session_path

    get admin_posts_path
    assert_redirected_to new_session_path
  end
end
