require "test_helper"

# The site logo as its own auto-submitting resource: PATCH swaps it the moment
# a file is picked, DELETE reverts to the wordmark — never part of the
# settings form's Save, so an upload can't collide with a removal.
class AdminSettingsLogosTest < ActionDispatch::IntegrationTest
  test "logo management is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    patch admin_settings_logo_path, params: { site: { logo: png_upload } }
    assert_response :not_found
  end

  test "picking a file attaches the logo immediately" do
    sign_in_as users(:admin)

    patch admin_settings_logo_path, params: { site: { logo: png_upload } }
    assert_redirected_to admin_settings_path
    assert accounts(:merovex).site.logo.attached?
    assert_equal "logo.png", accounts(:merovex).site.logo.filename.to_s
  end

  test "an unacceptable file bounces with the validation message and nothing sticks" do
    sign_in_as users(:admin)

    file = Rack::Test::UploadedFile.new(StringIO.new("plain text"), "text/plain", original_filename: "notes.txt")
    patch admin_settings_logo_path, params: { site: { logo: file } }

    assert_redirected_to admin_settings_path
    assert flash[:alert].present?
    assert_not accounts(:merovex).site.reload.logo.attached?
  end

  test "an SVG logo previews as a currentColor-tinted mask, not an <img>" do
    sign_in_as users(:admin)
    svg = %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40"><path d="M0 0h120v40H0z"/></svg>)
    file = Rack::Test::UploadedFile.new(StringIO.new(svg), "image/svg+xml", original_filename: "mark.svg")

    patch admin_settings_logo_path, params: { site: { logo: file } }
    follow_redirect!

    assert_select "span.logo-tint.logo-upload__preview[role=img]" do |(span)|
      assert_includes span["style"], "--logo-url: url(data:image/svg+xml;base64,"
      assert_includes span["style"], "--logo-ratio: 3.0"
    end
    assert_select "img.logo-upload__preview", count: 0
  end

  test "DELETE removes the logo and returns to the wordmark" do
    sign_in_as users(:admin)
    patch admin_settings_logo_path, params: { site: { logo: png_upload } }
    assert accounts(:merovex).site.logo.attached?

    delete admin_settings_logo_path
    assert_redirected_to admin_settings_path
    assert_not accounts(:merovex).site.reload.logo.attached?
  end

  private
    def png_upload
      Rack::Test::UploadedFile.new(file_fixture("avatar.png"), "image/png", original_filename: "logo.png")
    end
end
