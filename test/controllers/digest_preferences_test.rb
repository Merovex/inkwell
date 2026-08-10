require "test_helper"

# The one-click cadence links in the digest footer — tokened, no login.
class DigestPreferencesTest < ActionDispatch::IntegrationTest
  test "a tokened link changes cadence without signing in" do
    user = users(:alice)
    get digest_preference_path(cadence: "off", token: user.generate_token_for(:digest_preferences))

    assert_response :success
    assert_equal "off", user.reload.digest_cadence
  end

  test "an invalid token is a bare 404" do
    get digest_preference_path(cadence: "off", token: "not-a-real-token")
    assert_response :not_found
  end
end
