require "test_helper"

class BroadcastTest < ActiveSupport::TestCase
  test "a record can be broadcast only once" do
    records(:kickoff).create_broadcast!

    assert_raises(ActiveRecord::RecordInvalid) { records(:kickoff).create_broadcast! }
  end

  test "post returns the record's current version" do
    broadcast = records(:kickoff).create_broadcast!

    assert_equal posts(:kickoff), broadcast.post
  end

  test "sent? reflects the sent_at stamp" do
    broadcast = records(:kickoff).create_broadcast!
    assert_not broadcast.sent?

    broadcast.update!(sent_at: Time.current)
    assert broadcast.sent?
  end

  test "rates use the newsletter denominators, and are nil when empty" do
    broadcast = records(:kickoff).create_broadcast!(
      recipients_count: 10, delivered_count: 8, opened_count: 4, clicked_count: 2)

    assert_in_delta 0.8,  broadcast.delivery_rate, 0.001  # 8 / 10 recipients
    assert_in_delta 0.5,  broadcast.open_rate,     0.001  # 4 / 8 delivered
    assert_in_delta 0.25, broadcast.click_rate,    0.001  # 2 / 8 delivered

    empty = Broadcast.new
    assert_nil empty.delivery_rate
    assert_nil empty.open_rate
  end

  test "issue! freezes the title and the body with its tip-in, once" do
    posts(:kickoff).update!(content: "<p>Hello.</p>", tipin: "<p>Free novella inside.</p>")
    broadcast = records(:kickoff).create_broadcast!

    broadcast.issue!
    assert broadcast.issued?
    assert_equal posts(:kickoff).title, broadcast.issue_title
    assert_match "Free novella inside", broadcast.issue_html

    posts(:kickoff).update!(title: "Retitled", content: "<p>Changed.</p>")
    assert_no_changes -> { broadcast.reload.attributes.slice("issue_title", "issue_html", "issued_at") } do
      broadcast.issue!
    end
  end

  test "issue! renders embedded images at the mailer host, not the static tenant host" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file_fixture("avatar.png").open, filename: "avatar.png", content_type: "image/png")
    posts(:kickoff).update!(content: %(<action-text-attachment sgid="#{blob.attachable_sgid}"></action-text-attachment>))
    broadcast = records(:kickoff).create_broadcast!

    broadcast.issue!

    host = Rails.application.config.action_mailer.default_url_options[:host]
    assert_match %r{<img[^>]+src="https?://#{Regexp.escape(host)}/rails/active_storage/}, broadcast.issue_html
  end

  test "to_param leads with the frozen title and ends in the permanent slug" do
    broadcast = records(:kickoff).create_broadcast!.tap(&:issue!)
    posts(:kickoff).update!(title: "Retitled")

    assert_equal "kickoff-notes-for-the-winter-issue-#{broadcast.slug}", broadcast.reload.to_param
  end
end
