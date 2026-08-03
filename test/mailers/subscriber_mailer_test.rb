require "test_helper"

class SubscriberMailerTest < ActionMailer::TestCase
  test "confirmation carries the tokened confirm and unsubscribe links" do
    subscriber = Subscriber.create!(email_address: "reader@example.com")
    token = subscriber.generate_token_for(:confirmation)

    email = SubscriberMailer.confirmation(subscriber, token)

    assert_equal [ "reader@example.com" ], email.to
    assert_match accounts(:merovex).site.site_name, email.subject
    # Assert on the decoded parts — the raw MIME soft-wraps the long token.
    [ email.text_part, email.html_part ].each do |part|
      assert_match "/newsletter/confirm/#{token}", part.decoded
      assert_match %r{/newsletter/unsubscribe/}, part.decoded
    end
  end

  test "a domain-less account's links land on the apex slug path, not the app host" do
    Rails.configuration.x.app_host = "app.kindredquill.example"
    account = Account.create_with_owner(name: "Slugonly Press", owner: users(:bob))
    subscriber = Current.with_account(account) { Subscriber.create!(email_address: "reader@example.com") }
    token = subscriber.generate_token_for(:confirmation)

    email = SubscriberMailer.confirmation(subscriber, token)

    assert_match %r{https://kindredquill\.example/#{account.slug}/newsletter/confirm/}, email.text_part.decoded
  ensure
    Rails.configuration.x.app_host = nil
  end

  test "re_engagement carries the keep and unsubscribe links" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    token = subscriber.generate_token_for(:unsubscribe)

    email = SubscriberMailer.re_engagement(subscriber, token)

    assert_equal [ "reader@example.com" ], email.to
    assert_match accounts(:merovex).site.site_name, email.subject
    [ email.text_part, email.html_part ].each do |part|
      assert_match "/newsletter/keep/#{token}", part.decoded
      assert_match "/newsletter/unsubscribe/#{token}", part.decoded
    end
  end

  test "confirmation sends from the marketing identity and replies to the contact email" do
    accounts(:merovex).update!(contact_email: "press@example.com")
    subscriber = Subscriber.create!(email_address: "reader@example.com")

    email = SubscriberMailer.confirmation(subscriber, subscriber.generate_token_for(:confirmation))

    # From must be the Postmark-verified merovex.press identity, not the raw
    # contact address; replies still route to the press.
    assert_equal [ "press@example.com" ], email.reply_to
    assert_not_equal [ "press@example.com" ], email.from
    assert_equal [ "newsletter@merovex.press" ], email.from
    # Transactional stream, never the bulk Broadcast stream.
    assert_equal "outbound", email["message-stream"].value
  end
end
