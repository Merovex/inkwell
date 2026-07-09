require "test_helper"

# Public author persona pages + structured data.
class AuthorsTest < ActionDispatch::IntegrationTest
  test "the author page shows the bio and their published work" do
    author = originate_author("Ben Wilson", bio: "<p>Writes science fiction.</p>")
    posts(:kickoff).update_column(:author_record_id, author.record_id)

    get author_page_path(author)
    assert_response :success
    assert_select "h1", text: "Ben Wilson"
    assert_select ".press-article__body", text: /Writes science fiction/
    assert_select ".press-article-card__title", text: posts(:kickoff).title
    assert_match '"@type":"Person"', response.body   # JSON-LD
  end

  test "the author page canonicalizes a bare-id slug" do
    author = originate_author("Ben Wilson")

    get "/authors/#{author.record_id}"
    assert_redirected_to author_page_path(author)
  end

  test "a blog post links its byline to the author page" do
    author = originate_author("Ben Wilson")
    posts(:kickoff).update_column(:author_record_id, author.record_id)

    get "/blog/#{records(:kickoff).to_slug}"
    assert_response :success
    assert_select ".press-article__byline a[href=?]", author_page_path(author), text: "Ben Wilson"
    assert_match '"@type":"Article"', response.body   # JSON-LD
  end

  private
    def originate_author(name, **attrs)
      Author.new(name: name, creator: users(:admin), **attrs).tap { |a| Record.originate(a) }
    end
end
