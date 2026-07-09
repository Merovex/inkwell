# A store buy-link for a book, hanging off the book's Record (the stable
# identity) so links live independently of the book's versioned content. The
# platform is auto-detected from the URL, which is also stripped of tracking
# query params. clicks is a mutable counter for the public redirect (later).
class Distributor < ApplicationRecord
  belongs_to :record

  # host fragments that identify each store; anything unmatched is "other".
  PLATFORM_PATTERNS = {
    "amazon"       => %w[amazon. amzn.to],
    "apple_books"  => %w[books.apple.com],
    "kobo"         => %w[kobo.com],
    "barnes_noble" => %w[barnesandnoble.com],
    "google_play"  => %w[play.google.com],
    "smashwords"   => %w[smashwords.com],
    "lulu"         => %w[lulu.com]
  }.freeze

  enum :platform, %w[amazon apple_books kobo barnes_noble google_play smashwords lulu other].index_by(&:itself)

  validates :url, presence: true, uniqueness: { scope: :record_id, message: "has already been added" }
  before_validation :normalize_url_and_platform

  # The store a URL points at (an enum key), or "other" when nothing matches.
  def self.detect_platform(url)
    PLATFORM_PATTERNS.each do |platform, hosts|
      return platform if hosts.any? { |host| url.to_s.include?(host) }
    end
    "other"
  end

  # Drop the query string — buy links don't need tracking params, and it keeps
  # the per-book uniqueness check honest.
  def self.clean_url(url)
    url.to_s.strip.split("?").first
  end

  # A human label; most platforms humanize cleanly, a few need special-casing.
  def display_name
    { "apple_books" => "Apple Books", "barnes_noble" => "Barnes & Noble",
      "google_play" => "Google Play Books" }.fetch(platform, platform.to_s.humanize)
  end

  def click
    increment!(:clicks)
  end

  private
    def normalize_url_and_platform
      return if url.blank?
      self.url = self.class.clean_url(url)
      self.platform = self.class.detect_platform(url)
    end
end
