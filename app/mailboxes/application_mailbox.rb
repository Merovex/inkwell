class ApplicationMailbox < ActionMailbox::Base
  # One inbound address today: support@kindredquill.com (SES receipt rule →
  # S3 → SNS → the :ses ingress). Everything routes to SupportMailbox, which
  # lands the message as a Missive (docs/email-architecture.md, stream 4).
  routing all: :support
end
