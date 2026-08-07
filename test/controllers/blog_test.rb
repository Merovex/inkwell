require "test_helper"

# The public blog. A published post is reachable by its canonical id-first slug;
# a scheduled post is reachable early only through its keyed preview slug (so a
# broadcast can go out before publish without a dead link), and 404s otherwise.
class BlogTest < ActionDispatch::IntegrationTest
  test "a published post renders and canonicalizes a bare-id slug" do
    get "/posts/#{records(:kickoff).id}"
    assert_redirected_to "/posts/#{records(:kickoff).to_slug}"
    follow_redirect!
    assert_response :success
  end

  test "a scheduled post is reachable only via its keyed slug, and noindexed" do
    record = schedule_a_post

    get "/posts/#{record.to_slug}"
    assert_response :success
    assert_equal "noindex", response.headers["X-Robots-Tag"]

    get "/posts/#{record.id}"        # bare id, no key
    assert_response :not_found

    wrong = record.to_slug[0..-2] + (record.to_slug[-1] == "0" ? "1" : "0")
    get "/posts/#{wrong}"            # wrong key
    assert_response :not_found
  end

  test "a crawler probe with a format extension 404s instead of 500ing" do
    get "/posts/robots.txt"
    assert_response :not_found
  end

  test "the blog list shows the author's excerpt when set" do
    posts(:kickoff).update!(excerpt: "A crisp, SEO-friendly summary.")

    get posts_path
    assert_response :success
    assert_select ".press-article-card__desc", text: /crisp, SEO-friendly summary/
  end

  test "a published article sends a public etag and 304s on revalidation" do
    get "/posts/#{records(:kickoff).to_slug}"
    assert_response :success
    assert response.headers["ETag"].present?, "conditional-GET etag"
    assert_match "public", response.headers["Cache-Control"]

    get "/posts/#{records(:kickoff).to_slug}", headers: { "If-None-Match" => response.headers["ETag"] }
    assert_response :not_modified
  end

  test "a scheduled preview is never shared-cached and stays noindex" do
    record = schedule_a_post

    get "/posts/#{record.to_slug}"
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "noindex", response.headers["X-Robots-Tag"]
  end

  test "once published the old keyed link 301s to the clean slug" do
    record = schedule_a_post
    keyed = record.to_slug
    record.recordable.publish(creator: users(:alice))

    get "/posts/#{keyed}"
    assert_redirected_to "/posts/#{record.reload.to_slug}"
  end

  private
    def schedule_a_post
      record = records(:typography)
      record.revise(event: :scheduled, status: :scheduled, creator: users(:alice), published_at: 1.week.from_now)
      record.reload
    end
end
