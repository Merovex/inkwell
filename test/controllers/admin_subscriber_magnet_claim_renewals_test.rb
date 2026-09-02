require "test_helper"

# Staff-side "send them the book" from the roster, keyed by (subscriber,
# magnet): mints the Grant when the reader never held one (magnets that
# postdate their signup), restores a spent allowance on an existing one, and
# mails a fresh claim link. Unconfirmed states are refused; other presses'
# subscribers and magnets are out of reach.
class AdminSubscriberMagnetClaimRenewalsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @magnet = Magnet.new(title: "The Bargain")
    @magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "the-bargain.epub", content_type: "application/epub+zip")
    @magnet.save!
    @subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    sign_in_as users(:admin)
  end

  test "sends the claim link to a confirmed subscriber who never held a grant, minting it" do
    assert_difference -> { @magnet.grants.count }, 1 do
      assert_enqueued_emails 1 do
        post admin_subscriber_magnet_claim_renewal_path(@subscriber, @magnet)
      end
    end
    assert_redirected_to admin_subscribers_path(state: "confirmed")
    assert @magnet.grants.exists?(subscriber: @subscriber)
  end

  test "re-sending to an existing grant reuses it and restores a spent allowance" do
    grant = @magnet.grant_to(@subscriber)
    Grant::DOWNLOAD_LIMIT.times { grant.downloads.create!(format: "epub") }

    travel 1.hour do
      assert_no_difference -> { @magnet.grants.count } do
        assert_enqueued_emails 1 do
          post admin_subscriber_magnet_claim_renewal_path(@subscriber, @magnet)
        end
      end
    end

    assert_not grant.reload.exhausted?
    assert_equal Grant::DOWNLOAD_LIMIT, grant.downloads.count
  end

  test "refuses an unconfirmed subscriber without minting a grant" do
    @subscriber.update!(status: :pending, confirmed_at: nil)

    assert_no_difference -> { Grant.count } do
      assert_no_enqueued_emails do
        post admin_subscriber_magnet_claim_renewal_path(@subscriber, @magnet)
      end
    end
    assert_redirected_to admin_subscribers_path(state: "pending")
  end

  test "another press's subscriber or magnet is out of reach" do
    other = Account.create!(name: "Other Press", owner: users(:alice))
    foreign_magnet, foreign_subscriber = Current.with_account(other) do
      magnet = Magnet.new(title: "Elsewhere")
      magnet.epub.attach(io: StringIO.new("x"), filename: "e.epub", content_type: "application/epub+zip")
      magnet.save!
      [ magnet, Subscriber.create!(email_address: "other@example.com", status: :confirmed, confirmed_at: Time.current) ]
    end

    post admin_subscriber_magnet_claim_renewal_path(@subscriber, foreign_magnet)
    assert_response :not_found

    post admin_subscriber_magnet_claim_renewal_path(foreign_subscriber, @magnet)
    assert_response :not_found
  end

  test "the claim email carries just that magnet's link" do
    email = MagnetMailer.claim(@magnet.grant_to(@subscriber))

    assert_equal [ "reader@example.com" ], email.to
    assert_equal "Your The Bargain download link", email.subject
    assert_match %r{/claim/}, email.text_part.body.to_s
  end
end
