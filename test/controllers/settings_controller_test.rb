require "test_helper"

# System settings (/admin/settings): the account's Site identity, editable
# only by the domain admin. Denials render the same 404 as anywhere else.
class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "the admin sees the identity form" do
    sign_in_as users(:admin)

    get admin_settings_path
    assert_response :success
    assert_select "input[name='site[site_name]']"
    assert_select "input[name='site[tagline]']"
    assert_select "input[name='site[contact_email]']"
    # Multipart is load-bearing for the logo upload.
    assert_select "form[action=?][enctype=?]", admin_settings_path, "multipart/form-data"
  end

  test "the admin updates the identity" do
    sign_in_as users(:admin)

    patch admin_settings_path, params: { site: { site_name: "Verkilo Press", tagline: "New tagline" } }
    assert_redirected_to admin_settings_path
    assert_equal "Verkilo Press", accounts(:merovex).site.site_name
    assert_equal "New tagline", accounts(:merovex).site.tagline
  end

  test "a blank site name is rejected" do
    sign_in_as users(:admin)

    patch admin_settings_path, params: { site: { site_name: "" } }
    assert_response :unprocessable_entity
    assert accounts(:merovex).site.site_name.present?
  end

  test "the handle saves through the settings form onto the account" do
    sign_in_as users(:admin)

    patch admin_settings_path, params: { site: { site_name: "Merovex Press", handle: "Merovex" } }
    assert_redirected_to admin_settings_path
    assert_equal "merovex", accounts(:merovex).reload.handle
  end

  test "a reserved handle rejects the whole save — both models or neither" do
    sign_in_as users(:admin)

    patch admin_settings_path, params: { site: { site_name: "Renamed", handle: "noreply" } }
    assert_response :unprocessable_entity
    assert_nil accounts(:merovex).reload.handle
    assert_not_equal "Renamed", accounts(:merovex).site.site_name
  end

  test "the availability check answers free, taken (with a counter-offer), and reserved" do
    other = Account.create_with_owner(name: "Other Press", owner: users(:bob))
    other.update!(handle: "taken-name")
    sign_in_as users(:admin)

    get admin_handle_availability_path(value: "merovex")
    assert_response :success
    assert response.parsed_body["available"]

    get admin_handle_availability_path(value: "taken-name")
    body = response.parsed_body
    assert_not body["available"]
    assert body["taken"]
    assert_match(/\Ataken-name-\d{4}\z/, body["suggestion"])

    get admin_handle_availability_path(value: "noreply")
    assert_not response.parsed_body["available"]
  end

  test "a non-admin cannot see or change settings" do
    sign_in_as users(:bob)

    get admin_settings_path
    assert_response :not_found

    patch admin_settings_path, params: { site: { site_name: "Hijacked" } }
    assert_response :not_found
    assert_not_equal "Hijacked", accounts(:merovex).site.site_name
  end

  test "the public site reflects the configured identity" do
    accounts(:merovex).site.update!(site_name: "Verkilo Press", tagline: "Wonders await")

    get root_path
    assert_response :success
    assert_select ".wordmark", text: "Verkilo Press"
    assert_select "title", text: /Verkilo Press/
  end
end
