require "test_helper"

# The standing pages in the backend (/admin/pages): four seeded rows, edited
# and published, never created or deleted.
class AdminPagesTest < ActionDispatch::IntegrationTest
  test "pages are admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_pages_path
    assert_response :not_found
  end

  test "the index lists the four pages in their declared order" do
    sign_in_as users(:admin)

    get admin_pages_path
    assert_response :success
    assert_select ".list__item", count: 4
    assert_select ".list__item:first-child h3", text: "About"
  end

  test "the page is addressed by its slug, not a record id" do
    sign_in_as users(:admin)

    get edit_admin_page_path("privacy")
    assert_response :success
    assert_select "input[name='page[title]'][value=?]", "Privacy Policy"
  end

  test "saving a published page versions it and keeps the slug" do
    sign_in_as users(:admin)

    assert_difference -> { Page.count }, 1 do
      patch admin_page_path("about"), params: { page: { title: "About Us", content: "<p>Hello.</p>" } }
    end
    assert_redirected_to admin_pages_path

    page = accounts(:merovex).page("about")
    assert_equal "About Us", page.title
    assert_includes page.content.to_s, "Hello."
    assert_equal "about", page.slug
  end

  test "publishing is a resource: DELETE takes the page off the site, POST puts it back" do
    sign_in_as users(:admin)

    delete admin_page_publish_path("terms")
    assert_not accounts(:merovex).page("terms").published?

    post admin_page_publish_path("terms")
    assert accounts(:merovex).page("terms").published?
  end

  test "there is no way to delete a standing page — the route doesn't exist" do
    assert_raises ActionController::RoutingError do
      Rails.application.routes.recognize_path(admin_page_path("about"), method: :delete)
    end
  end

  test "an unknown slug 404s" do
    sign_in_as users(:admin)

    get edit_admin_page_path("pricing")
    assert_response :not_found
  end
end
