require "test_helper"

# Comments under a forum message: the same spine mechanics as under a post,
# through the parent-agnostic commentable helpers.
class MessagesCommentsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "the message page renders its thread with the prompt aimed at the message's composer" do
    get admin_message_path(records(:welcome))
    assert_response :success
    assert_select "#comments .comment__body", text: /first reply/
    assert_select "turbo-frame#new_comment a.comment__prompt[href=?]", new_admin_message_comment_path(records(:welcome))
  end

  test "create originates a comment record parented to the message" do
    assert_difference -> { records(:welcome).comments.count } do
      post admin_message_comments_path(records(:welcome)), params: { comment: { content: "<p>Welcome!</p>" } }
    end

    record = records(:welcome).children.order(:id).last
    assert_redirected_to admin_message_path(records(:welcome), anchor: "comment_#{record.id}")
  end

  test "shallow comment actions resolve back to the message page" do
    patch admin_comment_path(records(:welcome_comment)), params: { comment: { content: "<p>Edited reply.</p>" } }
    assert_redirected_to admin_message_path(records(:welcome), anchor: "comment_#{records(:welcome_comment).id}")

    delete admin_comment_path(records(:welcome_comment))
    assert_redirected_to admin_message_path(records(:welcome))
    assert records(:welcome_comment).reload.trashed?
  end

  test "the copy-link menu points at the message URL" do
    get admin_message_path(records(:welcome))
    assert_select "[data-clipboard-text-value=?]",
      admin_message_url(records(:welcome), anchor: "comment_#{records(:welcome_comment).id}")
  end
end
