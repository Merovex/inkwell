require "test_helper"

# The Mission Control jobs dashboard at /jobs: platform staff (root) only,
# riding the app's own session auth (Admin::JobsBaseController).
class JobsDashboardTest < ActionDispatch::IntegrationTest
  test "signed out is sent to sign in" do
    get mission_control_jobs_path
    # Literal path: after an engine request the test session's own helpers
    # would carry the /jobs script name.
    assert_redirected_to "/session/new"
  end

  test "a member gets the same 404 as a missing record" do
    sign_in_as users(:bob)
    get mission_control_jobs_path
    assert_response :not_found
  end

  test "root sees the dashboard" do
    sign_in_as users(:alice)
    get mission_control_jobs_path
    follow_redirect! while response.redirect?
    assert_response :success
  end

  private
    def mission_control_jobs_path = "/jobs"
end
