require "test_helper"

class MissiveMailerTest < ActionMailer::TestCase
  # ADR 0029's line: a contact-form submitter is an unverified stranger until
  # the confirmation link is clicked, so this is the one mail — with the
  # subscriber confirmation — that must not carry the author's reply address.
  test "the confirmation carries no reply-to, even when the site has an address" do
    accounts(:merovex).update!(contact_email: "press@example.com")
    missive = Missive.create!(name: "Stranger", email_address: "someone@example.com",
      subject: "Hello", body: "Just saying hi.")

    email = MissiveMailer.confirmation(missive, missive.generate_token_for(:confirmation))

    assert_nil email.reply_to
    assert_equal [ "someone@example.com" ], email.to
  end
end
