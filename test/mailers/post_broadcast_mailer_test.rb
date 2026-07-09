require "test_helper"

class PostBroadcastMailerTest < ActionMailer::TestCase
  test "issue carries the post, view-in-browser link, and unsubscribe" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)

    assert_equal ["reader@example.com"], email.to
    assert_equal posts(:kickoff).title, email.subject
    assert_match records(:kickoff).to_slug, email.text_part.decoded
    assert_match %r{/newsletter/unsubscribe/}, email.text_part.decoded
    assert_match "List-Unsubscribe=One-Click", email["List-Unsubscribe-Post"].to_s
  end

  test "issue tags the message with Mailgun variables for event mapping" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)

    vars = JSON.parse(email["X-Mailgun-Variables"].to_s)
    assert_equal broadcast.id, vars["broadcast_id"]
    assert_equal subscriber.id, vars["subscriber_id"]
  end
end
