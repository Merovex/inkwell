require "test_helper"

# System settings (/admin/settings): the singleton install identity, editable
# only by the domain admin. Denials render the same 404 as anywhere else.
class SettingsControllerTest < ActionDispatch::IntegrationTest
  test "the admin sees the identity form" do
    sign_in_as users(:admin)

    get admin_settings_path
    assert_response :success
    assert_select "input[name='setting[site_name]']"
    assert_select "input[name='setting[tagline]']"
    assert_select "input[name='setting[contact_email]']"
    # Multipart is load-bearing for the logo upload.
    assert_select "form[action=?][enctype=?]", admin_settings_path, "multipart/form-data"
  end

  test "the admin updates the identity" do
    sign_in_as users(:admin)

    patch admin_settings_path, params: { setting: { site_name: "Verkilo Press", tagline: "New tagline" } }
    assert_redirected_to admin_settings_path
    assert_equal "Verkilo Press", Setting.current.site_name
    assert_equal "New tagline", Setting.current.tagline
  end

  test "a blank site name is rejected" do
    sign_in_as users(:admin)

    patch admin_settings_path, params: { setting: { site_name: "" } }
    assert_response :unprocessable_entity
    assert Setting.current.site_name.present?
  end

  test "a non-admin cannot see or change settings" do
    sign_in_as users(:bob)

    get admin_settings_path
    assert_response :not_found

    patch admin_settings_path, params: { setting: { site_name: "Hijacked" } }
    assert_response :not_found
    assert_not_equal "Hijacked", Setting.current.site_name
  end

  test "the public site reflects the configured identity" do
    Setting.current.update!(site_name: "Verkilo Press", tagline: "Wonders await")

    get root_path
    assert_response :success
    assert_select ".press-brand__word", text: "Verkilo Press"
    assert_select "title", text: /Verkilo Press/
  end
end
