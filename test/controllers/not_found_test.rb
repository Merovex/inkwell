require "test_helper"

# The universal 404: every scoped lookup miss (bad id, trashed record, wrong
# type, someone else's yours-only content) renders the friendly in-app page
# with the way back to where they just were.
class NotFoundTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "a bogus id renders the styled 404, not an exception" do
    get message_path(id: 999_999)
    assert_response :not_found
    assert_select ".empty__title", text: "There's nothing at this address"
  end

  test "a cross-type probe 404s — a post's record id is nothing on the forum" do
    get message_path(records(:kickoff))
    assert_response :not_found

    get post_path(records(:welcome))
    assert_response :not_found
  end

  test "with a same-origin referer the page leads back to where they just were" do
    get message_path(id: 999_999), headers: { "Referer" => messages_url }
    assert_response :not_found
    assert_select ".empty__actions a.button--primary[href=?]", messages_url, text: "Go back"
    assert_select ".empty__actions a[href=?]", root_path, text: "Go home"
  end

  test "an off-site referer is not offered as the way back" do
    get message_path(id: 999_999), headers: { "Referer" => "https://evil.example/" }
    assert_response :not_found
    assert_select ".empty__actions a[href=?]", "https://evil.example/", count: 0
    assert_select ".empty__actions a.button--primary[href=?]", root_path, text: "Go home"
  end

  test "a version probe under the wrong record 404s" do
    other = posts(:typography)
    get post_change_path(records(:kickoff), other)
    assert_response :not_found
  end
end
