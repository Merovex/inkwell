require "test_helper"

class DropMailerTest < ActionMailer::TestCase
  setup do
    creator = users(:admin)
    @drip = Drip.new(title: "Welcome", active: true, creator:)
    Record.originate(@drip)
    @drop = Drop.new(subject: "Welcome aboard", delay_days: 0, creator:)
    @drop.body = "<p>Glad you're here.</p>"
    Record.originate(@drop, parent: @drip.record)

    @sub = Subscriber.create!(email_address: "reader@example.com", status: :confirmed, confirmed_at: Time.current)
    @stream = @drip.enroll(@sub)
  end

  test "renders the drop's Lexxy body and subject" do
    email = DropMailer.step(@stream, @drop)

    assert_equal [ "reader@example.com" ], email.to
    assert_equal "Welcome aboard", email.subject
    [ email.text_part, email.html_part ].each do |part|
      assert_match "Glad you're here", part.decoded
    end
  end

  test "sends from the site's broadcast address and carries a one-click unsubscribe" do
    accounts(:merovex).update!(contact_email: "press@example.com")
    email = DropMailer.step(@stream, @drop)

    # No handle claimed and no BYOD domain live → the shared-lane fallback.
    assert_equal [ "noreply@#{Account.shared_sending_domain}" ], email.from
    assert_equal [ "press@example.com" ], email.reply_to
    assert_match %r{/newsletter/unsubscribe/}, email["List-Unsubscribe"].to_s
    assert_equal "List-Unsubscribe=One-Click", email["List-Unsubscribe-Post"].to_s
    assert_equal "broadcast", email["message-stream"].value
    assert_equal "true", email.track_opens
    assert_equal "HtmlAndText", email.track_links
    assert_equal @drop.record_id.to_s, email.metadata["drop_record_id"]
  end

  test "tags the message with the marketing config set and drop/subscriber tags" do
    email = DropMailer.step(@stream, @drop)
    settings = email.delivery_method.settings

    assert_equal Rails.application.credentials.dig(:ses, :marketing_config_set), settings[:configuration_set_name]
    tags = settings[:email_tags].index_by { |t| t[:name] }
    assert_equal @drop.record_id.to_s, tags["drop_record_id"][:value]
    assert_equal @sub.id.to_s, tags["subscriber_id"][:value]
  end

  test "a magnet-bearing drop mints the subscriber's grant and carries the claim link" do
    magnet = Magnet.new(title: "The Bargain")
    magnet.epub.attach(io: StringIO.new("epub bytes"), filename: "b.epub", content_type: "application/epub+zip")
    magnet.save!
    @drop.update!(magnet: magnet)

    email = nil
    assert_difference -> { Grant.count }, 1 do
      email = DropMailer.step(@stream, @drop).tap(&:message)  # render mints the grant
    end

    grant = magnet.grants.find_by!(subscriber: @sub)
    [ email.text_part, email.html_part ].each do |part|
      assert_match "Get The Bargain", part.decoded
      assert_match %r{/claim/}, part.decoded
    end
    # A re-send reuses the grant rather than minting a second key.
    assert_no_difference -> { Grant.count } do
      DropMailer.step(@stream, @drop).message
    end
    assert_equal grant, magnet.grants.find_by!(subscriber: @sub)
  end

  test "a magnet-less drop carries no claim button" do
    email = DropMailer.step(@stream, @drop)
    [ email.text_part, email.html_part ].each do |part|
      assert_no_match %r{/claim/}, part.decoded
    end
  end

  test "stamps the site tenant once the account's tenant is provisioned" do
    assert_nil DropMailer.step(@stream, @drop).delivery_method.settings[:tenant_name]

    @sub.account.update!(ses_tenant_provisioned_at: Time.current)
    email = DropMailer.step(@stream, @drop)
    assert_equal @sub.account.ses_tenant_name, email.delivery_method.settings[:tenant_name]
  end
end
