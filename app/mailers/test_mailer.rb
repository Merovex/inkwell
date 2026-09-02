class TestMailer < ApplicationMailer
  default from: "ben@merovex.com"

  # Postmark smoke test. The HTML/text bodies live in the views — on this
  # Rails version ActionMailer ignores Postmark's html_body: option when
  # templates exist (it leaks into a stray header) and raises MissingTemplate
  # without them. track_opens and message_stream pass through to the Postmark
  # payload as TrackOpens / MessageStream.
  def hello
    mail(
      subject: "Hello from Postmark",
      to: "ben@merovex.com",
      from: "ben@merovex.com",
      track_opens: "true",
      message_stream: "outbound")
  end
end
