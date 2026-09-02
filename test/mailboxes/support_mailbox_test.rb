require "test_helper"

# Mail-in support: inbound email at support@ lands as a confirmed Missive on
# the designated account. No autoresponder; dupes and own-domain mail drop.
class SupportMailboxTest < ActionMailbox::TestCase
  test "an inbound email becomes a confirmed PLATFORM missive (no account)" do
    assert_difference -> { Missive.count }, 1 do
      receive_inbound_email_from_mail \
        from: %(Reader Jane <jane@example.com>),
        to: "support@kindredquill.com",
        subject: "Login trouble",
        body: "The sign-in code never arrived."
    end

    missive = Missive.last
    assert_equal "Reader Jane", missive.name
    assert_equal "jane@example.com", missive.email_address
    assert_equal "Login trouble", missive.subject
    assert_match "never arrived", missive.body
    assert missive.confirmed_at.present?, "mail-in missives are born confirmed"
    assert_nil missive.account, "platform mail belongs to the App, not a Site"
    assert missive.source_message_id.present?
  end

  test "a redelivered notification does not create a second missive" do
    # Action Mailbox already drops byte-identical sources; the mailbox's
    # source_message_id guard covers re-wrapped redeliveries — same
    # Message-ID, different bytes (SNS re-encoding, added transport headers).
    mail = Mail.new(from: "jane@example.com", to: "support@kindredquill.com",
                    subject: "Hello", body: "Once only", message_id: "<once@example.com>")
    assert_difference -> { Missive.count }, 1 do
      receive_inbound_email_from_source(mail.to_s)
      receive_inbound_email_from_source("X-SES-Redelivery: 1\r\n" + mail.to_s)
    end
  end

  test "mail from our own sending domains is dropped, not bounced" do
    assert_no_difference -> { Missive.count } do
      inbound = receive_inbound_email_from_mail \
        from: "noreply@auth.merovex.press",
        to: "support@kindredquill.com",
        subject: "Undeliverable", body: "loop bait"
      assert inbound.processed?, "dropped quietly, not bounced"
    end
  end

  test "SES setup-notification probes are dropped" do
    assert_no_difference -> { Missive.count } do
      receive_inbound_email_from_mail \
        from: "no-reply-aws@amazon.com", to: "support@kindredquill.com",
        subject: "Amazon SES Setup Notification", body: "You received this message because..."
    end
  end

  test "an html-only message is stripped to text" do
    receive_inbound_email_from_mail \
      from: "jane@example.com", to: "support@kindredquill.com", subject: "Rich" do |mail|
        mail.html_part = Mail::Part.new do
          content_type "text/html; charset=UTF-8"
          body "<html><body><p>Please <strong>help</strong> me.</p><style>p{color:red}</style></body></html>"
        end
      end

    assert_match "Please help me.", Missive.last.body.squish
    assert_no_match(/</, Missive.last.body)
  end
end
