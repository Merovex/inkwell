require "test_helper"

# Public marketing surface added for the author showcase: RSS, SEO meta,
# sitemap, legal pages, and the buy-link click-through.
class PublicPagesTest < ActionDispatch::IntegrationTest
  test "the blog RSS feed lists published posts" do
    get "/blog/feed.rss"
    assert_response :success
    assert_equal "application/rss+xml", response.media_type
    assert_includes response.body, "<rss"
    assert_includes response.body, posts(:kickoff).title
  end

  test "public pages carry open graph, canonical, and feed autodiscovery" do
    get root_path
    assert_response :success
    assert_select "meta[property=?]", "og:title"
    assert_select "link[rel=?][href=?]", "canonical", root_url
    assert_select "link[rel=?][type=?]", "alternate", "application/rss+xml"
  end

  test "robots.txt points crawlers at the sitemap" do
    get "/robots.txt"
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match %r{Sitemap: https?://[^/]+/sitemap\.xml}, response.body
  end

  test "the home page carries WebSite structured data" do
    get root_path
    assert_match '"@type":"WebSite"', response.body
  end

  test "the sitemap lists published post urls" do
    get "/sitemap.xml"
    assert_response :success
    assert_includes response.body, "<urlset"
    assert_includes response.body, blog_post_url(records(:kickoff).to_slug)
  end

  test "legal pages render the admin-authored rich text" do
    Setting.current.update!(privacy_policy: "<p>We respect your cookies.</p>", terms: "<p>Be excellent.</p>")

    get privacy_path
    assert_response :success
    assert_select ".press-article__body", text: /respect your cookies/

    get terms_path
    assert_select ".press-article__body", text: /Be excellent/
  end

  test "the footer links to a legal page only when it has content" do
    Setting.current.update!(privacy_policy: "<p>present</p>", terms: "")

    get root_path
    assert_select "a[href=?]", privacy_path
    assert_select "a[href=?]", terms_path, count: 0
  end

  test "a buy link counts the click and redirects to the store" do
    record = Record.create!(recordable_type: "Book", creator: users(:alice))
    distributor = Distributor.create!(record: record, url: "https://www.amazon.com/dp/B000")

    assert_difference -> { distributor.reload.clicks }, 1 do
      get buy_path(distributor)
    end
    assert_redirected_to "https://www.amazon.com/dp/B000"
  end
end
