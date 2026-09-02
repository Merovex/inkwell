require "test_helper"

# THE Phase 1 exit spec (ADR 0017), permanent: a second account with one of
# everything, and proof that account 1 sees none of it — in the admin, on the
# public site, and by direct id probe. If this file fails, tenant isolation
# is broken; it never leaves the suite.
class TenantIsolationTest < ActionDispatch::IntegrationTest
  APP_HOST = "app.kindredquill.example"

  setup do
    Rails.configuration.x.app_host = APP_HOST
    @merovex = accounts(:merovex)

    # Deliberately a plain member: per-account authority flows from owner_id.
    @rival_owner = User.create!(email_address: "rival@example.com", name: "Rival Owner")
    @rival = Account.create!(name: "Rival Press", owner: @rival_owner, domain: "rival.example")
    AccountUser.create!(account: @rival, user: @rival_owner)

    Current.with_account(@rival) do
      @rival_post = Record.originate(Post.new(title: "Rival Post", body: Body.create!,
        status: "published", published_at: 1.hour.ago, creator: @rival_owner))
      @rival_book = Record.originate(Book.new(title: "Rival Book", body: Body.create!,
        status: "published", published_at: 1.hour.ago, creator: @rival_owner))
      @rival_message = Record.originate(Message.new(title: "Rival Message", body: Body.create!,
        status: "published", published_at: 1.hour.ago, creator: @rival_owner))
      @rival_author = Record.originate(Author.new(name: "Rival Persona", creator: @rival_owner))
      Missive.create!(name: "Rival Fan", email_address: "fan@example.com",
        subject: "Rival Missive", body: "hello", confirmed_at: Time.current)
    end
  end

  teardown do
    Rails.configuration.x.app_host = nil
  end

  test "account 1's admin lists none of account 2's content" do
    host! APP_HOST
    sign_in_as users(:admin)

    { "posts" => "Rival Post", "books" => "Rival Book", "forum" => "Rival Message",
      "authors" => "Rival Persona", "missives" => "Rival Missive" }.each do |path, title|
      get "/#{@merovex.slug}/admin/#{path}"
      assert_response :success
      assert_no_match title, response.body, "account 1 admin /#{path} leaked '#{title}'"
    end
  end

  test "account 2's admin sees its own content (the leak checks aren't vacuous)" do
    host! APP_HOST
    sign_in_as @rival_owner

    get "/#{@rival.slug}/admin/books"
    assert_response :success
    assert_match "Rival Book", response.body
  end

  test "a direct id probe across accounts is a 404" do
    host! APP_HOST
    sign_in_as users(:admin)

    get "/#{@merovex.slug}/admin/posts/#{@rival_post.id}"
    assert_response :not_found

    get "/#{@merovex.slug}/admin/books/#{@rival_book.id}"
    assert_response :not_found
  end

  test "audience data is per-account: subscribers, broadcasts, visits" do
    merovex_subscriber = Current.with_account(@merovex) do
      Subscriber.create!(email_address: "reader@example.com", status: "confirmed", confirmed_at: Time.current)
    end
    Ahoy::Visit.create!(visit_token: "v1", visitor_token: "p1", started_at: 1.hour.ago, account_id: @merovex.id)

    host! APP_HOST
    sign_in_as @rival_owner

    get "/#{@rival.slug}/admin/subscribers"
    assert_response :success
    assert_no_match merovex_subscriber.email_address.split("@").first, response.body

    get "/#{@rival.slug}/admin/broadcasts"
    assert_response :success

    # Visits outlived the analytics dashboard that read them (they still feed
    # the weekly digest's per-post reads), so the scoping proof moved off the
    # HTTP surface and onto the association the tenancy guard watches.
    assert_not_includes @rival.ahoy_visits.pluck(:visitor_token), "p1"
    assert_includes @merovex.ahoy_visits.pluck(:visitor_token), "p1"
  end

  test "a circle's discussions belong to the circle, never to any account" do
    circle = Circle.create_with_owner(name: "Swap Circle", owner: @rival_owner)
    Current.with_bucket(circle) do
      Record.originate(Message.new(title: "Circle only", content: "swap terms",
        creator: @rival_owner, status: :published, published_at: Time.current))
    end

    # A circle discussion is a Message, but bucket-scoped: it hangs off the
    # circle, and neither press's records include it.
    record = circle.records.messages.sole
    assert_equal circle, record.bucket
    assert_not_includes @merovex.records.messages.pluck(:id), record.id
    assert_not_includes @rival.records.messages.pluck(:id), record.id
  end

  test "each domain serves only its own public site" do
    host! @rival.domain
    get "/posts"
    assert_response :success
    assert_match "Rival Post", response.body

    host! @merovex.domain
    get "/posts"
    assert_response :success
    assert_no_match "Rival Post", response.body

    get "/books"
    assert_no_match "Rival Book", response.body
  end
end
