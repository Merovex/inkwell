require "test_helper"

class WeeklyDigestMailerTest < ActionMailer::TestCase
  test "the digest goes to the user from the platform lane, naming the site" do
    account = accounts(:merovex)  # owned by alice
    week_of = Date.new(2026, 8, 3)
    broadcast = records(:kickoff).create_broadcast!
    broadcast.update!(sent_at: week_of + 1.day, recipients_count: 5, delivered_count: 5)

    email = WeeklyDigestMailer.weekly(users(:alice), week_of)

    assert_equal [ users(:alice).email_address ], email.to
    assert_equal [ "noreply@notify.kindredquill.com" ], email.from  # platform bulk voice
    assert_match account.name, email.subject
    assert_match account.name, email.text_part.decoded
    assert_match "delivered", email.text_part.decoded
    # The HTML part renders the mockup's card without error.
    assert_match "Subscribers", email.html_part.decoded
    assert_match account.name, email.html_part.decoded
  end

  test "rides the platform-circles bulk tenant and marketing config set" do
    week_of = Date.new(2026, 8, 3)
    records(:kickoff).create_broadcast!.update!(sent_at: week_of + 1.day, recipients_count: 1, delivered_count: 1)

    email = WeeklyDigestMailer.weekly(users(:alice), week_of)
    settings = email.delivery_method.settings

    assert_equal "platform-circles", settings[:tenant_name]
    assert_equal Rails.application.credentials.dig(:ses, :marketing_config_set), settings[:configuration_set_name]
  end
end
