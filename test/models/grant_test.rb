require "test_helper"

class GrantTest < ActiveSupport::TestCase
  setup do
    magnet = Magnet.new(title: "The Bargain")
    magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "b.epub", content_type: "application/epub+zip")
    magnet.save!
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    @grant = magnet.grant_to(subscriber)
  end

  test "the claim token resolves back to the grant until it expires" do
    token = @grant.claim_token
    assert_equal @grant, Grant.find_by_token_for(:claim, token)

    travel Grant::TOKEN_LIFETIME + 1.day do
      assert_nil Grant.find_by_token_for(:claim, token)
    end
  end

  test "the token stays resolvable across downloads — only the cap exhausts it" do
    token = @grant.claim_token
    assert_not @grant.exhausted?

    Grant::DOWNLOAD_LIMIT.times { @grant.downloads.create!(format: "epub") }

    assert @grant.exhausted?
    assert_equal @grant, Grant.find_by_token_for(:claim, token), "a spent grant still resolves — the page says so, the download refuses"
  end

  test "renewing restores the allowance and keeps the downloads that spent it" do
    Grant::DOWNLOAD_LIMIT.times { @grant.downloads.create!(format: "epub") }
    assert @grant.exhausted?

    travel 1.hour do
      @grant.renew

      assert_not @grant.exhausted?
      assert_equal Grant::DOWNLOAD_LIMIT, @grant.downloads.count, "the audit trail outlives the counter"

      Grant::DOWNLOAD_LIMIT.times { @grant.downloads.create!(format: "epub") }
      assert @grant.exhausted?, "the fresh allowance is the same size, not unlimited"
    end
  end
end
