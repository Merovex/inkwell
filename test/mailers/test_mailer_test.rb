require "test_helper"

class TestMailerTest < ActionMailer::TestCase
  test "hello" do
    mail = TestMailer.hello
    assert_equal "Hello from Postmark", mail.subject
    assert_equal [ "ben@merovex.com" ], mail.to
    assert_equal [ "ben@merovex.com" ], mail.from
    assert_match "<strong>Hello</strong>", mail.body.encoded
  end
end
