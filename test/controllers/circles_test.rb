require "test_helper"

class CirclesTest < ActionDispatch::IntegrationTest
  test "a member sees the circle board" do
    sign_in_as users(:bob)

    get circle_path(circles(:writers))
    assert_response :success
    assert_match "Welcome to the circle", response.body
  end

  test "a non-member gets the same 404 as a missing record" do
    sign_in_as users(:admin) # root, but not a member of this circle

    get circle_path(circles(:writers))
    assert_response :not_found
  end

  test "signed-out visitors are bounced to sign-in" do
    get circle_path(circles(:writers))
    assert_redirected_to new_session_path
  end

  test "a member posts to the board and the message is owned by the circle" do
    sign_in_as users(:bob)

    assert_difference -> { circles(:writers).messages.count }, 1 do
      post circle_messages_path(circles(:writers)),
        params: { circle_message: { title: "Standup", content: "Wrote 500 words today." } }
    end
    assert_response :redirect

    message = circles(:writers).messages.order(:record_id).last
    assert_equal "Circle", message.record.bucket_type
    assert_equal circles(:writers).id, message.record.bucket_id
  end

  test "an empty post is rejected with a nudge" do
    sign_in_as users(:bob)

    assert_no_difference -> { circles(:writers).messages.count } do
      post circle_messages_path(circles(:writers)), params: { circle_message: { title: "", content: "" } }
    end
    assert_redirected_to circle_path(circles(:writers))
  end
end
