module SubscribersHelper
  # The signup page a partner reported (Subscriber#source_url), as a link when
  # it is really a web address and as plain text when it isn't. The value comes
  # from a third party and lands in an href, so the scheme is checked against
  # http/https rather than trusted — javascript: and data: URLs never reach the
  # page — and the href is rebuilt from the parsed URI rather than echoed.
  def signup_page(url)
    uri = URI.parse(url.to_s)
    return url.to_s unless uri.is_a?(URI::HTTP) && uri.host.present?

    link_to url.to_s, uri.to_s, rel: "noopener noreferrer", target: "_blank"
  rescue URI::InvalidURIError
    url.to_s
  end

  # What became (or will become) of an address in a SubscriberImport — the
  # outcome strings SubscriberImport#outcomes produces, in reading order.
  SUBSCRIBER_IMPORT_OUTCOMES = {
    "invite"       => [ "New — will get a confirmation email", "Invited — confirmation email sent" ],
    "confirmed"    => "Already subscribed",
    "pending"      => "Already invited, not yet confirmed",
    "unsubscribed" => "Unsubscribed — left alone",
    "bounced"      => "Bounced — left alone",
    "complained"   => "Marked you as spam — left alone",
    "suppressed"   => "Blocked after bounces or complaints — skipped",
    "rejected"     => "Not a usable address — skipped"
  }.freeze

  def subscriber_import_outcome_label(outcome, sent:)
    label = SUBSCRIBER_IMPORT_OUTCOMES.fetch(outcome, outcome.humanize)
    label.is_a?(Array) ? label[sent ? 1 : 0] : label
  end

  def subscriber_import_outcome_order(outcome) = SUBSCRIBER_IMPORT_OUTCOMES.keys.index(outcome) || SUBSCRIBER_IMPORT_OUTCOMES.size
end
