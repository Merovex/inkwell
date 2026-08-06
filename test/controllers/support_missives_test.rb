require "test_helper"

# The platform support inbox: app-host /missives, root staff only, platform
# (accountless) missives only — a Site's contact-form mail never appears.
class SupportMissivesTest < ActionDispatch::IntegrationTest
  setup do
    Current.without_account do
      @platform = Missive.create!(account: nil, name: "Reader", email_address: "reader@example.com",
        subject: "Login trouble", body: "The code never came.", confirmed_at: Time.current)
    end
  end

  test "root staff read the platform inbox and the full message" do
    sign_in_as users(:admin) # fixture root? adjust below if member
    users(:admin).update!(role: :root)

    get missives_path
    assert_response :success
    assert_select ".list__title", text: "Login trouble"

    get missive_path(@platform)
    assert_response :success
    assert_match "The code never came.", response.body
  end

  test "a Site's contact-form missives do not appear in the platform inbox" do
    site_missive = Missive.create!(account: accounts(:merovex), name: "Fan",
      email_address: "fan@example.com", subject: "Site question", body: "Hi!", confirmed_at: Time.current)
    users(:admin).update!(role: :root)
    sign_in_as users(:admin)

    get missives_path
    assert_select ".list__title", text: "Site question", count: 0
  end

  test "non-root gets a bare 404" do
    sign_in_as users(:bob)

    get missives_path
    assert_response :not_found
  end
end
