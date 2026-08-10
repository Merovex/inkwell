require "test_helper"

# The platform people directory (/admin/users): every user, the circles they
# belong to, and the sites they own. Root staff only, like the support desk.
class StaffUsersTest < ActionDispatch::IntegrationTest
  test "root staff see every user with their circles and owned sites" do
    sign_in_as users(:alice)
    get staff_users_path

    assert_response :success
    assert_select ".list__title", text: "Alice Example"
    assert_select ".list__title", text: "Bob Example"
    # Circle affiliations ride as chips; owned sites link out by name.
    assert_select ".badge", text: "Writers Circle"
    assert_match "Merovex Press", response.body
  end

  test "the scoreboard shows real customer counts and projected economics" do
    sign_in_as users(:alice)
    get staff_users_path

    assert_response :success
    assert_select ".stat__label", text: "customers"
    assert_select ".stat__value", text: User.count.to_s
    assert_select ".stat__label", text: "LTV : CAC"
  end

  test "the directory is root-only" do
    sign_in_as users(:bob)
    get staff_users_path
    assert_response :not_found
  end

  test "the directory requires sign-in" do
    get staff_users_path
    assert_response :redirect
  end
end
