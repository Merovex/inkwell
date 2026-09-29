require "test_helper"

# The newsletter archive: a broadcast's browser view, frozen as it went out.
# Island page — tenant-scoped, anonymous, noindexed; the link partners and
# promo organizers check, so it must show the email-only tip-in and never
# drift when the post is edited later.
class IssuesTest < ActionDispatch::IntegrationTest
  setup do
    posts(:kickoff).update!(content: "<p>Hello.</p><p>{% tipin %}</p>", tipin: "<p>Free novella inside.</p>")
    @broadcast = records(:kickoff).create_broadcast!(sent_at: Time.zone.local(2026, 10, 1, 9), recipients_count: 1204)
    @broadcast.issue!
  end

  test "renders the frozen issue with its tip-in, send date, and reach, noindexed" do
    get issue_path(@broadcast)

    assert_response :success
    assert_select "h1", text: posts(:kickoff).title
    assert_select "article", text: /Free novella inside/
    assert_select "time[datetime=?]", "2026-10-01", text: "October 1, 2026"
    assert_match "to 1,204 subscribers", response.body
    assert_select "meta[name=robots][content=noindex]"
    assert_equal "noindex", response.headers["X-Robots-Tag"]
  end

  test "later edits to the post never reach the archive" do
    posts(:kickoff).update!(title: "Retitled", content: "<p>Typo fixed.</p>", tipin: "<p>New tip-in.</p>")

    get issue_path(@broadcast)

    assert_select "h1", text: "Kickoff notes for the winter issue"
    assert_no_match "Typo fixed", response.body
    assert_match "Free novella inside", response.body
  end

  test "a mangled title tail still resolves, 301ing to the canonical spelling" do
    get issue_path(id: "some-old-title-#{@broadcast.slug.downcase}")

    assert_redirected_to issue_path(@broadcast)
    assert_response :moved_permanently
  end

  test "a broadcast that hasn't been issued yet 404s" do
    @broadcast.update!(issue_title: nil, issue_html: nil, issued_at: nil)

    get issue_path(@broadcast)

    assert_response :not_found
  end

  test "a trashed post's archive 404s" do
    records(:kickoff).update!(trashed_at: Time.current)

    get issue_path(@broadcast)

    assert_response :not_found
  end

  test "another site's archive does not resolve here" do
    other = Account.create!(name: "Other Press", owner: users(:alice))
    records(:kickoff).update_columns(bucket_id: other.id)

    get issue_path(@broadcast)

    assert_response :not_found
  end
end
