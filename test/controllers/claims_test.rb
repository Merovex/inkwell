require "test_helper"

# The reader-magnet claim flow: tokened landing page, download POSTs that 302
# to a file URL, and the "send me a new link" renewal form. All island pages —
# tenant-scoped, anonymous, prefetch-safe (GET spends nothing).
class ClaimsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @magnet = Magnet.new(title: "The Bargain", description: "A prequel novella.")
    @magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "the-bargain.epub", content_type: "application/epub+zip")
    @magnet.save!
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    @grant = @magnet.grant_to(@subscriber)
  end

  test "a valid token lands on the claim page with a button per attached format" do
    get claim_path(token: @grant.claim_token)

    assert_response :success
    assert_select "h1", text: "The Bargain"
    assert_select "form input[name=kind][value=epub]"
    assert_select "form input[name=kind][value=pdf]", count: 0
  end

  test "an invalid, missing, or expired token lands on the renewal page" do
    get claim_path(token: "not-a-token")
    assert_response :not_found
    assert_select "form[action=?]", claim_renewal_path

    get claim_path
    assert_response :not_found

    token = @grant.claim_token
    travel Grant::TOKEN_LIFETIME + 1.day do
      get claim_path(token: token)
      assert_response :not_found
    end
  end

  test "a token minted for another press's grant does not resolve here" do
    other = Account.create!(name: "Other Press", owner: users(:alice))
    foreign_magnet = Current.with_account(other) do
      Magnet.new(title: "Elsewhere").tap do |magnet|
        magnet.epub.attach(io: StringIO.new("x"), filename: "e.epub", content_type: "application/epub+zip")
        magnet.save!
      end
    end
    foreign_sub = Current.with_account(other) do
      Subscriber.create!(email_address: "other@example.com", status: :confirmed, confirmed_at: Time.current)
    end
    foreign_grant = foreign_magnet.grant_to(foreign_sub)

    get claim_path(token: foreign_grant.claim_token)
    assert_response :not_found
  end

  test "downloading counts a Download and redirects to the file" do
    assert_difference -> { @grant.downloads.count }, 1 do
      post claim_downloads_path(token: @grant.claim_token), params: { kind: "epub" }
    end

    assert_response :redirect
    assert_match "the-bargain.epub", response.location
    assert_equal "epub", @grant.downloads.last.format
  end

  test "an unknown kind or an unattached format 404s without spending the cap" do
    assert_no_difference -> { Download.count } do
      post claim_downloads_path(token: @grant.claim_token), params: { kind: "exe" }
      assert_response :not_found
      post claim_downloads_path(token: @grant.claim_token), params: { kind: "pdf" }
      assert_response :not_found
    end
  end

  test "a spent grant gets the renewal page instead of a file" do
    Grant::DOWNLOAD_LIMIT.times { @grant.downloads.create!(format: "epub") }

    get claim_path(token: @grant.claim_token)
    assert_response :gone

    assert_no_difference -> { Download.count } do
      post claim_downloads_path(token: @grant.claim_token), params: { kind: "epub" }
    end
    assert_response :gone
  end

  test "renewal mails fresh claim links to the address on file" do
    assert_enqueued_emails 1 do
      post claim_renewal_path, params: { email_address: "Reader@Example.com" }
    end
    assert_redirected_to claim_renewal_sent_path
  end

  test "renewal is silent for unknown addresses and grantless subscribers — same page either way" do
    Subscriber.create!(email_address: "grantless@example.com", status: :confirmed, confirmed_at: Time.current)

    assert_no_enqueued_emails do
      post claim_renewal_path, params: { email_address: "nobody@example.com" }
      assert_redirected_to claim_renewal_sent_path
      post claim_renewal_path, params: { email_address: "grantless@example.com" }
      assert_redirected_to claim_renewal_sent_path
    end
  end

  test "a tripped honeypot gets the same page and no email" do
    assert_no_enqueued_emails do
      post claim_renewal_path, params: { email_address: "reader@example.com", Subscriber::HONEYPOT_FIELD => "gotcha" }
    end
    assert_redirected_to claim_renewal_sent_path
  end
end
