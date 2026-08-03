require "test_helper"

class PostBroadcastMailerTest < ActionMailer::TestCase
  test "issue carries the post, view-in-browser link, and unsubscribe" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)

    assert_equal [ "reader@example.com" ], email.to
    assert_equal posts(:kickoff).title, email.subject
    assert_match records(:kickoff).to_slug, email.text_part.decoded
    assert_match %r{/newsletter/unsubscribe/}, email.text_part.decoded
    assert_match "List-Unsubscribe=One-Click", email["List-Unsubscribe-Post"].to_s
  end

  test "issue rides Postmark's broadcast stream with tracking and id metadata" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)

    assert_equal "broadcast", email["message-stream"].value
    # Open/link tracking on so Postmark emits Open/Click events; the ids ride as
    # Metadata so Webhooks::PostmarkController can map events back to this delivery.
    assert_equal "true", email.track_opens
    assert_equal "HtmlAndText", email.track_links
    assert_equal broadcast.id.to_s, email.metadata["broadcast_id"]
    assert_equal subscriber.id.to_s, email.metadata["subscriber_id"]
  end

  test "issue tags the message with the SES config set and message tags for event mapping" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)
    settings = email.delivery_method.settings

    assert_equal Rails.application.credentials.dig(:ses, :marketing_config_set), settings[:configuration_set_name]
    tags = settings[:email_tags].index_by { |t| t[:name] }
    assert_equal broadcast.id.to_s, tags["broadcast_id"][:value]
    assert_equal subscriber.id.to_s, tags["subscriber_id"][:value]
  end
end
