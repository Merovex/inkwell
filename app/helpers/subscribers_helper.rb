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
end
