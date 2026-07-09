require "test_helper"

# The public blog. A published post is reachable by its canonical id-first slug;
# a scheduled post is reachable early only through its keyed preview slug (so a
# broadcast can go out before publish without a dead link), and 404s otherwise.
class BlogTest < ActionDispatch::IntegrationTest
  test "a published post renders and canonicalizes a bare-id slug" do
    get "/blog/#{records(:kickoff).id}"
    assert_redirected_to "/blog/#{records(:kickoff).to_slug}"
    follow_redirect!
    assert_response :success
  end

  test "a scheduled post is reachable only via its keyed slug, and noindexed" do
    record = schedule_a_post

    get "/blog/#{record.to_slug}"
    assert_response :success
    assert_equal "noindex", response.headers["X-Robots-Tag"]

    get "/blog/#{record.id}"        # bare id, no key
    assert_response :not_found

    wrong = record.to_slug[0..-2] + (record.to_slug[-1] == "0" ? "1" : "0")
    get "/blog/#{wrong}"            # wrong key
    assert_response :not_found
  end

  test "once published the old keyed link 301s to the clean slug" do
    record = schedule_a_post
    keyed = record.to_slug
    record.recordable.publish(creator: users(:alice))

    get "/blog/#{keyed}"
    assert_redirected_to "/blog/#{record.reload.to_slug}"
  end

  private
    def schedule_a_post
      record = records(:typography)
      record.revise(event: :scheduled, status: :scheduled, creator: users(:alice), published_at: 1.week.from_now)
      record.reload
    end
end
