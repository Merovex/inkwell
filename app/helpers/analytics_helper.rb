module AnalyticsHelper
  # The path portion of a landing-page URL (host is redundant on the dashboard),
  # falling back to the raw value if it doesn't parse.
  def url_path(url)
    URI(url).path.presence || url
  rescue URI::InvalidURIError
    url
  end
end
