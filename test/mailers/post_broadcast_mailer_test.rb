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

  # Regression: the Action Text blob partial calls ApplicationHelper#attachment_variation,
  # which mailers don't get unless ApplicationMailer pulls it in — the first
  # broadcast with an embedded image 500'd in production without it.
  test "issue renders a post with an embedded image attachment" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("avatar.png").open, filename: "avatar.png", content_type: "image/png"
    )
    posts(:kickoff).update!(content: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)

    assert_match "<img", email.html_part.decoded
  end

  test "issue splices the tip-in at the marker, in both parts" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    posts(:kickoff).update!(content: "<p>Hello.</p><p>{% tipin %}</p>", tipin: "<p>Free novella inside.</p>")
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)

    assert_match "Free novella inside", email.html_part.decoded
    assert_match "Free novella inside", email.text_part.decoded
    assert_no_match(/\{%\s*tipin/, email.html_part.decoded)
  end

  test "issue's reader-facing links land on the account's own domain, never the app host" do
    subscriber = Subscriber.create!(email_address: "reader@example.com", status: :confirmed)
    broadcast = records(:kickoff).create_broadcast!

    email = PostBroadcastMailer.issue(broadcast, subscriber)

    # The merovex fixture carries domain: merovex.press — every public link
    # (view-in-browser, unsubscribe, one-click header) must ride it.
    assert_match %r{https://merovex\.press/.*#{records(:kickoff).to_slug}}, email.text_part.decoded
    assert_match %r{https://merovex\.press/newsletter/unsubscribe/}, email.text_part.decoded
    assert_match %r{\Ahttps://merovex\.press/}, email["List-Unsubscribe"].to_s.delete_prefix("<")
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
