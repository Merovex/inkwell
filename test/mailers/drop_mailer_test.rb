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

  test "sends from the marketing identity and carries a one-click unsubscribe" do
    Setting.current.update!(contact_email: "press@example.com")
    email = DropMailer.step(@stream, @drop)

    assert_equal [ Rails.application.credentials.dig(:ses, :marketing_from) ], email.from
    assert_equal [ "press@example.com" ], email.reply_to
    assert_match %r{/newsletter/unsubscribe/}, email["List-Unsubscribe"].to_s
    assert_equal "List-Unsubscribe=One-Click", email["List-Unsubscribe-Post"].to_s
  end

  test "tags the message with the marketing config set and drop/subscriber tags" do
    email = DropMailer.step(@stream, @drop)
    settings = email.delivery_method.settings

    assert_equal Rails.application.credentials.dig(:ses, :marketing_config_set), settings[:configuration_set_name]
    tags = settings[:email_tags].index_by { |t| t[:name] }
    assert_equal @drop.record_id.to_s, tags["drop_record_id"][:value]
    assert_equal @sub.id.to_s, tags["subscriber_id"][:value]
  end
end
