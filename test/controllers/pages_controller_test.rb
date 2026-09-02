require "test_helper"

# The public Merovex Press front-of-house pages. The standing pages (About,
# Privacy, Terms) are Pages on the spine now — authored at /admin/pages, not
# in System settings.
class PagesControllerTest < ActionDispatch::IntegrationTest
  test "the About page renders the About page's content, heading and all" do
    write_page "about", "<h1>About us</h1><p>We publish <em>wonders</em>.</p>"

    get about_path
    assert_response :success
    assert_select ".press-body em", text: "wonders"
    # The body carries the heading (the theme's contract), so the chrome
    # doesn't add a second one.
    assert_select ".press-display-lg", count: 0
    assert_select ".press-body h1", text: "About us"
  end

  test "the About page falls back gracefully with nothing written" do
    accounts(:merovex).site.update!(site_name: "Verkilo Press")

    get about_path
    assert_response :success
    assert_select ".press-display-lg", text: "About Verkilo Press"
    assert_select ".press-body", text: /coming soon/
  end

  test "an unpublished About page reads as an empty one" do
    write_page "about", "<p>Draft copy nobody should see.</p>"
    accounts(:merovex).page("about").unpublish

    get about_path
    assert_response :success
    assert_select ".press-body", text: /coming soon/
  end

  private
    def write_page(slug, html)
      accounts(:merovex).page(slug).record.save_edit(content: html, creator: users(:alice))
    end
end
