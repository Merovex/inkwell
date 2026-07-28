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
