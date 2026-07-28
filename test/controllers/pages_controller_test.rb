require "test_helper"

# The public Merovex Press front-of-house pages.
class PagesControllerTest < ActionDispatch::IntegrationTest
  test "the About page renders the configured About blurb" do
    accounts(:merovex).site.update!(site_name: "Verkilo Press", description: "<p>We publish <em>wonders</em>.</p>")

    get about_path
    assert_response :success
    assert_select ".press-display-lg", text: "About Verkilo Press"
    assert_select ".press-body em", text: "wonders"
  end

  test "the About page falls back gracefully with no blurb set" do
    accounts(:merovex).site.update!(description: "")

    get about_path
    assert_response :success
    assert_select ".press-body", text: /coming soon/
  end
end
