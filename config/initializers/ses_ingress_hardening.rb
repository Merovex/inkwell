# The SES ingress endpoint is public; internet scanners POST garbage at it.
# aws-actionmailbox-ses (0.2.0) raises Aws::Json::ParseError on a non-JSON
# body, which 500s and pages Honeybadger (first observed 2026-08-05 — our own
# empty-body probe). Malformed input from strangers is a 400, not an error;
# real SNS traffic is well-formed and signed, so this can't mask anything.
Rails.application.config.to_prepare do
  next unless defined?(ActionMailbox::Ingresses::Ses::InboundEmailsController)

  ActionMailbox::Ingresses::Ses::InboundEmailsController.class_eval do
    rescue_from Aws::Json::ParseError, JSON::ParserError do
      head :bad_request
    end
  end
end
