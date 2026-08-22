require "test_helper"

# The copy a standing page opens with, so a brand-new site never publishes a
# blank About, Privacy, or Terms.
class PageStarterTest < ActiveSupport::TestCase
  test "the copy is rendered in the site's own name and contact address" do
    html = Page::Starter.html_for("privacy", accounts(:merovex))

    assert_includes html, "Merovex Press"
    assert_includes html, "hello@merovex.press"
  end

  test "an account with no contact address yet gets a sentence that still reads" do
    accounts(:merovex).update!(contact_email: nil)

    assert_includes Page::Starter.html_for("terms", accounts(:merovex)), "the contact form on this site"
  end

  test "the body carries its own heading — the page renders it as the whole page" do
    assert_match %r{\A<h1>}, Page::Starter.html_for("about", accounts(:merovex))
  end

  test "development's template annotations never reach stored content" do
    assert_not_includes Page::Starter.html_for("about", accounts(:merovex)), "<!-- BEGIN"
  end

  test "the newsletter page has no starter — its band supplies the defaults" do
    assert_nil Page::Starter.html_for("newsletter", accounts(:merovex))
  end
end
