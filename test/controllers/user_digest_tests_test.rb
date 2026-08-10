require "test_helper"

# The in-app "send me a test" button for the weekly digest.
class UserDigestTestsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "sends the signed-in user their own digest and returns to settings" do
    sign_in_as users(:alice)  # owns merovex

    assert_enqueued_emails 1 do
      post user_digest_test_path
    end
    assert_redirected_to user_settings_path
  end

  test "requires sign-in" do
    post user_digest_test_path
    assert_response :redirect
  end
end
