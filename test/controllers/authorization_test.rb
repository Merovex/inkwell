require "test_helper"

# The policy layer (app/policies): posts and messages are managed by their
# creator or the domain admin; unpublished work is invisible to everyone
# else. Denials render the same 404 as a missing record.
class AuthorizationTest < ActionDispatch::IntegrationTest
  test "someone else's published post can be read but not managed" do
    sign_in_as users(:bob)

    get admin_post_path(records(:kickoff))
    assert_response :success
    # No edit affordances: no Edit link, no rename form, menu offers history only.
    assert_select ".canvas__head a", text: "Edit", count: 0
    assert_select ".editable__input", count: 0
    assert_select ".menu__item", text: "Move to trash", count: 0
    assert_select ".menu__item", text: "View History"

    get edit_admin_post_path(records(:kickoff))
    assert_response :not_found

    patch admin_post_path(records(:kickoff)), params: { post: { title: "Hijacked" } }
    assert_response :not_found

    delete admin_post_path(records(:kickoff))
    assert_response :not_found
    assert_not records(:kickoff).reload.trashed?

    delete admin_post_publish_path(records(:kickoff))
    assert_response :not_found
    assert records(:kickoff).recordable.published?
  end

  test "the admin manages anyone's content" do
    sign_in_as users(:admin)

    patch admin_message_path(records(:welcome)), params: { message: { title: "Admin renamed" } }
    assert_redirected_to admin_message_path(records(:welcome))
    assert_equal "Admin renamed", records(:welcome).reload.recordable.title

    delete admin_post_path(records(:kickoff))
    assert records(:kickoff).reload.trashed?
  end

  test "someone else's draft is invisible: show, edit, and history all 404" do
    sign_in_as users(:bob)

    get admin_message_path(records(:roadmap))
    assert_response :not_found

    get edit_admin_message_path(records(:roadmap))
    assert_response :not_found

    get admin_message_events_path(records(:roadmap))
    assert_response :not_found

    get admin_post_path(records(:typography))
    assert_response :not_found
  end

  test "the creator and the admin see the draft" do
    sign_in_as users(:alice)
    get admin_message_path(records(:roadmap))
    assert_response :success

    sign_in_as users(:admin)
    get admin_message_path(records(:roadmap))
    assert_response :success
  end

  test "drafts lists and counts are yours-only; the admin sees everyone's" do
    sign_in_as users(:bob)

    get admin_drafts_path
    assert_select ".list__title", text: posts(:typography).title, count: 0
    get admin_posts_path
    assert_select "a[href=?]", admin_drafts_path, count: 0

    delete admin_draft_path(records(:typography))
    assert_response :not_found
    assert Record.exists?(records(:typography).id)

    sign_in_as users(:admin)
    get admin_drafts_path
    assert_select ".list__title", text: posts(:typography).title
  end

  test "commenting and boosting follow visibility — no replies to hidden drafts" do
    sign_in_as users(:bob)

    post admin_message_comments_path(records(:roadmap)), params: { comment: { content: "<p>Peek.</p>" } }
    assert_response :not_found

    assert_no_difference "Boost.count" do
      post admin_record_boosts_path(records(:roadmap)), params: { boost: { content: "👀" } }
    end
    assert_response :not_found
  end

  test "a tampered category_id is a validation error, not a 500" do
    sign_in_as users(:alice)

    assert_no_difference "Message.count" do
      post admin_messages_path, params: { message: { title: "FK probe", content: "<p>x</p>", category_id: 999_999 } }
    end
    assert_response :unprocessable_entity
  end
end
