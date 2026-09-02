require "test_helper"

# A member's public face: the circles they're in, scoped by who's looking —
# all of yours on your own page, only the ones you share on someone else's.
class ProfilesTest < ActionDispatch::IntegrationTest
  test "your own profile lists all your circles" do
    sign_in_as users(:bob)
    get profile_path(users(:bob))

    assert_response :success
    assert_select ".perma-header__title", text: "Bob Example"
    assert_select ".list__title", text: "Writers Circle"
  end

  test "another member's profile shows only circles you share" do
    sign_in_as users(:alice)
    get profile_path(users(:bob))

    assert_response :success
    # Alice and Bob both sit in Writers Circle — a shared affiliation.
    assert_select ".list__title", text: "Writers Circle"
  end

  test "a circle you don't share stays hidden on someone else's profile" do
    stranger = User.create!(name: "Stranger", email_address: "stranger@example.com")
    sign_in_as stranger
    get profile_path(users(:bob))

    assert_response :success
    assert_select ".list__title", text: "Writers Circle", count: 0
    assert_select ".empty__title", text: "No shared circles"
  end

  test "profiles require sign-in" do
    get profile_path(users(:bob))
    assert_response :redirect
  end
end
