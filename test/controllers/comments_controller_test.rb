require "test_helper"

class CommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "post page renders the thread and the comment prompt, no composer" do
    get post_path(records(:kickoff))
    assert_response :success
    assert_select "#comments .comment__body", text: /interview piece/
    assert_select "#comments .menu__item", text: "Copy link"
    # The composer isn't on the page — the prompt fetches it into its frame.
    assert_select "turbo-frame#new_comment a.comment__prompt[href=?]", new_post_comment_path(records(:kickoff))
    assert_select "#new_comment lexxy-editor", count: 0
  end

  test "new swaps the composer into the prompt's frame" do
    get new_post_comment_path(records(:kickoff))
    assert_response :success
    assert_select "turbo-frame#new_comment lexxy-editor"
    assert_select "turbo-frame#new_comment form[action=?]", post_comments_path(records(:kickoff))
    assert_select "turbo-frame#new_comment input[type=submit][value=?]", "Add this comment"
    # Drafts key to the record being commented on, so they survive Never mind.
    assert_select "turbo-frame#new_comment form[data-controller=autosave][data-autosave-key-value=?]",
      "Record/#{records(:kickoff).id}/comment"
    # Never mind re-fetches the post page into the frame — back to the prompt.
    assert_select "turbo-frame#new_comment a[data-turbo-frame=new_comment]", text: "Never mind"
  end

  test "create originates a comment record parented to the post" do
    assert_difference -> { records(:kickoff).comments.count } do
      post post_comments_path(records(:kickoff)), params: { comment: { content: "<p>Nice.</p>" } }
    end

    record = records(:kickoff).children.order(:id).last
    assert_redirected_to post_path(records(:kickoff), anchor: "comment_#{record.id}")
    assert_equal users(:alice), record.creator
  end

  test "create rejects a blank comment" do
    assert_no_difference -> { Comment.count } do
      post post_comments_path(records(:kickoff)), params: { comment: { content: "" } }
    end
    assert_redirected_to post_path(records(:kickoff), anchor: "new_comment")
  end

  test "edit renders the inline editor in the comment's frame" do
    get edit_comment_path(records(:kickoff_comment))
    assert_response :success
    assert_select "turbo-frame#comment_#{records(:kickoff_comment).id} lexxy-editor"
    # Edit drafts carry the current version id so stale ones get dropped.
    assert_select "form[data-autosave-key-value=?]", "Record/#{records(:kickoff_comment).id}/edit"
    assert_select "form[data-autosave-revision-value=?]", comments(:kickoff_comment).id.to_s
  end

  test "update lands as a tracked version and shows the Edited marker" do
    record = records(:kickoff_comment)

    assert_difference -> { record.versions.count } do
      patch comment_path(record), params: { comment: { content: "<p>Better.</p>" } }
    end

    assert_redirected_to post_path(records(:kickoff), anchor: "comment_#{record.id}")
    assert_equal "Better.", record.reload.recordable.content.to_plain_text

    follow_redirect!
    assert_select "turbo-frame#comment_#{record.id}", text: /Edited/
  end

  test "update with blank content re-renders the editor" do
    patch comment_path(records(:kickoff_comment)), params: { comment: { content: "" } }
    assert_response :unprocessable_entity
    assert_select "lexxy-editor"
  end

  test "destroy trashes the comment" do
    delete comment_path(records(:kickoff_comment))

    assert records(:kickoff_comment).reload.trashed?
    assert_redirected_to post_path(records(:kickoff))

    follow_redirect!
    assert_select "#comments .comment__body", count: 0
  end

  test "posts index shows the comment count" do
    get posts_path
    assert_select ".list__count", text: "1"
  end

  test "member actions are yours-only: someone else's comment 404s" do
    sign_in_as users(:bob)

    get edit_comment_path(records(:kickoff_comment))
    assert_response :not_found

    patch comment_path(records(:kickoff_comment)), params: { comment: { content: "<p>Hijacked.</p>" } }
    assert_response :not_found

    delete comment_path(records(:kickoff_comment))
    assert_response :not_found
    assert_not records(:kickoff_comment).reload.trashed?
  end

  test "the menu hides Edit and trash on someone else's comment" do
    sign_in_as users(:bob)

    get post_path(records(:kickoff))
    assert_select "#comments .menu__item", text: "Copy link"
    assert_select "#comments .menu__item", text: "Edit", count: 0
    assert_select "#comments .menu__item", text: "Move to trash", count: 0
  end
end
