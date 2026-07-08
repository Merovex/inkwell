require "test_helper"

class UserSettingsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:alice)
  end

  test "show renders the name form and the avatar well" do
    get admin_user_settings_path
    assert_response :success
    assert_select "input[name='user[name]'][value=?]", "Alice Example"
    assert_select ".settings__avatar input[type=file][accept=?]", User::AVATAR_CONTENT_TYPES.join(",")
    # Multipart is load-bearing: without it Turbo drops the file on submit.
    assert_select "form[action=?][enctype=?]", admin_user_avatar_path, "multipart/form-data"
    # No picture yet — no remove button.
    assert_select "button", text: "Remove picture and use initials", count: 0
  end

  test "update changes the display name" do
    patch admin_user_settings_path, params: { user: { name: "Alice B. Example" } }
    assert_redirected_to admin_user_settings_path
    assert_equal "Alice B. Example", users(:alice).reload.display_name
  end

  test "a blank name falls back to the email address" do
    patch admin_user_settings_path, params: { user: { name: "" } }
    assert_equal "alice@example.com", users(:alice).reload.display_name
  end

  test "uploading a picture attaches it and shows it in the avatar" do
    patch admin_user_avatar_path, params: { user: { avatar: fixture_file_upload("avatar.png", "image/png") } }

    assert_redirected_to admin_user_settings_path
    assert users(:alice).reload.avatar.attached?

    follow_redirect!
    assert_select ".settings__avatar img.avatar__img"
    assert_select "button", text: "Remove picture and use initials"
  end

  test "rejects a non-image upload" do
    patch admin_user_avatar_path, params: { user: { avatar: fixture_file_upload("avatar.txt", "text/plain") } }

    assert_redirected_to admin_user_settings_path
    assert_equal "Avatar must be a JPG, PNG, AVIF, or WebP image", flash[:alert]
    assert_not users(:alice).reload.avatar.attached?
  end

  test "removing the picture reverts to initials" do
    users(:alice).avatar.attach(io: file_fixture("avatar.png").open, filename: "avatar.png", content_type: "image/png")

    delete admin_user_avatar_path
    assert_redirected_to admin_user_settings_path
    assert_not users(:alice).reload.avatar.attached?

    follow_redirect!
    assert_select ".settings__avatar img.avatar__img", count: 0
  end

  test "the header avatar shows the picture once uploaded" do
    users(:alice).avatar.attach(io: file_fixture("avatar.png").open, filename: "avatar.png", content_type: "image/png")

    get admin_posts_path
    assert_select "button.avatar img.avatar__img"
  end
end
