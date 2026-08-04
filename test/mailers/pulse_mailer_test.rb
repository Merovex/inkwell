require "test_helper"

class PulseMailerTest < ActionMailer::TestCase
  test "the ask carries the question and rides the transactional identity" do
    circle = circles(:writers)
    pulse = Current.with_bucket(circle) do
      Record.originate(Pulse.new(question: "What did you ship?", creator: users(:alice)))
    end.recordable

    email = PulseMailer.ask(pulse, users(:bob), Date.current)

    assert_equal [ users(:bob).email_address ], email.to
    # Transactional support identity, not a press newsletter sender.
    assert_equal [ "support@kindredquill.com" ], email.from
    assert_match "What did you ship?", email.html_part.decoded
    # The question is the subject; the body links back to the pulse to answer.
    assert_equal "What did you ship?", email.subject
    assert_match %r{/circles/.+/pulses/}, email.html_part.decoded
  end
end
