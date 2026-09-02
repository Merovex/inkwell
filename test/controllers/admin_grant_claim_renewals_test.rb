require "test_helper"

# Staff-side re-send of one grant's claim link from the roster: a confirmed
# subscriber gets a fresh tokened email for that magnet alone; unconfirmed
# states are refused; other presses' grants are out of reach.
class AdminGrantClaimRenewalsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @magnet = Magnet.new(title: "The Bargain")
    @magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "the-bargain.epub", content_type: "application/epub+zip")
    @magnet.save!
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    @grant = @magnet.grant_to(@subscriber)
    sign_in_as users(:admin)
  end

  test "re-sends one magnet's claim link to a confirmed subscriber" do
    assert_enqueued_emails 1 do
      post admin_grant_claim_renewal_path(@grant)
    end
    assert_redirected_to admin_subscribers_path(state: "confirmed")
  end

  test "a staff re-send restores the reader's spent allowance too" do
    Grant::DOWNLOAD_LIMIT.times { @grant.downloads.create!(format: "epub") }

    travel 1.hour do
      post admin_grant_claim_renewal_path(@grant)
    end

    assert_not @grant.reload.exhausted?
    assert_equal Grant::DOWNLOAD_LIMIT, @grant.downloads.count
  end

  test "refuses an unconfirmed subscriber" do
    @subscriber.update!(status: :pending, confirmed_at: nil)

    assert_no_enqueued_emails do
      post admin_grant_claim_renewal_path(@grant)
    end
    assert_redirected_to admin_subscribers_path(state: "pending")
  end

  test "another press's grant is out of reach" do
    other = Account.create!(name: "Other Press", owner: users(:alice))
    foreign_grant = Current.with_account(other) do
      magnet = Magnet.new(title: "Elsewhere")
      magnet.epub.attach(io: StringIO.new("x"), filename: "e.epub", content_type: "application/epub+zip")
      magnet.save!
      magnet.grant_to(Subscriber.create!(email_address: "other@example.com", status: :confirmed, confirmed_at: Time.current))
    end

    post admin_grant_claim_renewal_path(foreign_grant)
    assert_response :not_found
  end

  test "the claim email carries just that magnet's link" do
    email = MagnetMailer.claim(@grant)

    assert_equal [ "reader@example.com" ], email.to
    assert_equal "Your The Bargain download link", email.subject
    assert_match %r{/claim/}, email.text_part.body.to_s
  end
end
