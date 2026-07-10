require "test_helper"

# Managing pen names — recordables on the spine, edited in place. Domain-admin only.
class AdminAuthorsTest < ActionDispatch::IntegrationTest
  test "author management is admin-only: a member gets a 404" do
    sign_in_as users(:bob)

    get admin_authors_path
    assert_response :not_found
  end

  test "creating an author originates a record and lands on edit for the avatar" do
    sign_in_as users(:admin)

    assert_difference -> { Record.authors.count }, 1 do
      post admin_authors_path, params: { author: { name: "Ben Wilson", bio: "<p>SF & fantasy.</p>" } }
    end

    author = Author.current.find_by(name: "Ben Wilson")
    assert_redirected_to edit_admin_author_path(author.record)
    assert author.default?, "the first author is the default"
  end

  test "editing mutates the current version in place" do
    author = originate_author("Ben")
    sign_in_as users(:admin)

    assert_no_difference -> { Author.count } do
      patch admin_author_path(author.record), params: { author: { name: "Ben Wilson" } }
    end
    assert_equal "Ben Wilson", author.record.reload.recordable.name
  end

  test "removing an author trashes it" do
    author = originate_author("Ben")
    sign_in_as users(:admin)

    delete admin_author_path(author.record)
    assert author.record.reload.trashed?
  end

  private
    def originate_author(name)
      Author.new(name: name, creator: users(:admin)).tap { |a| Record.originate(a) }
    end
end
