require "test_helper"

# The ungated direct-download flow: a slugged delivery page and grantless
# download POSTs. Island pages — tenant-scoped, anonymous, prefetch-safe
# (GET spends nothing); the link's job is delivery to readers already on
# the list, so there is no token and no cap, just the rate limit.
class DeliveriesTest < ActionDispatch::IntegrationTest
  setup do
    @magnet = Magnet.new(title: "The Bargain", description: "A prequel novella.")
    @magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "the-bargain.epub", content_type: "application/epub+zip")
    @magnet.save!
  end

  test "the canonical slug renders the delivery page with a button per attached format" do
    get delivery_path(@magnet)

    assert_response :success
    assert_select "h1", text: "The Bargain"
    assert_select "form input[name=kind][value=epub]"
    assert_select "form input[name=kind][value=pdf]", count: 0
  end

  test "a link minted before a title edit still resolves, 301ing to the canonical spelling" do
    stale = @magnet.to_param
    @magnet.update!(title: "The Bargain, Revised")

    get delivery_path(id: stale)

    assert_redirected_to delivery_path(@magnet)
    assert_response :moved_permanently
  end

  test "a case-mangled slug (the Crockford i/l/o forgivenesses) 301s to the canonical spelling" do
    get delivery_path(id: @magnet.to_param.downcase)

    assert_redirected_to delivery_path(@magnet)
    assert_response :moved_permanently
  end

  test "an unknown slug 404s" do
    get delivery_path(id: "no-such-book-B4DB4D")

    assert_response :not_found
  end

  test "another press's slug does not resolve here" do
    other = Account.create!(name: "Other Press", owner: users(:alice))
    foreign_magnet = Current.with_account(other) do
      Magnet.new(title: "Elsewhere").tap do |magnet|
        magnet.epub.attach(io: StringIO.new("x"), filename: "e.epub", content_type: "application/epub+zip")
        magnet.save!
      end
    end

    get delivery_path(id: foreign_magnet.to_param)

    assert_response :not_found
  end

  test "downloading counts a grantless Download against the magnet and redirects to the file" do
    assert_difference -> { @magnet.downloads.count }, 1 do
      post delivery_files_path(@magnet), params: { kind: "epub" }
    end

    assert_response :redirect
    assert_match "the-bargain.epub", response.location

    download = @magnet.downloads.last
    assert_nil download.grant
    assert_equal "epub", download.format
  end

  test "an unknown kind or an unattached format 404s without counting" do
    assert_no_difference -> { Download.count } do
      post delivery_files_path(@magnet), params: { kind: "exe" }
      assert_response :not_found
      post delivery_files_path(@magnet), params: { kind: "pdf" }
      assert_response :not_found
    end
  end
end
