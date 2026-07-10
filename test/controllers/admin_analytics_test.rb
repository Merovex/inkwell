require "test_helper"

# The public-traffic dashboard (Ahoy): domain-admin only, read-only.
class AdminAnalyticsTest < ActionDispatch::IntegrationTest
  test "the dashboard is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_analytics_path
    assert_response :not_found
  end

  test "the dashboard summarizes recent visits, views, and referrers" do
    visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
      started_at: 1.day.ago, landing_page: "https://example.com/blog", referring_domain: "google.com")
    Ahoy::Event.create!(visit: visit, name: "$view", time: 1.day.ago, properties: {})
    sign_in_as users(:admin)

    get admin_analytics_path
    assert_response :success
    assert_select ".analytics-stat__value", text: "1"          # one visit / one view
    assert_select ".analytics-section", text: /google\.com/     # top referrer
  end

  test "old visits fall outside the 30-day window" do
    Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: SecureRandom.uuid,
      started_at: 90.days.ago, landing_page: "https://example.com/")
    sign_in_as users(:admin)

    get admin_analytics_path
    assert_response :success
    assert_select ".analytics-stat__value", text: "0"
  end
end
