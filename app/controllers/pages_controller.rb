# Public-facing Merovex Press pages (the front of house). Anonymous — no session
# required — and rendered in the standalone "public" layout rather than the
# Inkwell admin chrome.
class PagesController < PublicController
  def home
    # Books for the home-page scroller: series order first (books within a
    # series by release date), then standalone titles by release date. A book
    # in multiple series appears once.
    linked = Installment.select(:book_record_id)
    in_series = Series.current.published.feed_ordered.flat_map do |series|
      series.books.published.reorder(:publication_date).to_a
    end
    standalone = Book.current.published.where.not(record_id: linked)
      .includes(:record, :depiction).order(:publication_date)
    @scroller_books = (in_series + standalone).uniq(&:record_id)
    fresh_when etag: [ @scroller_books, site_settings ], public: true
  end

  # Renders the About blurb an admin sets in System settings (Setting#description).
  def about
    fresh_when etag: site_settings, public: true
  end

  # Legal pages, authored as rich text in System settings. Cookies live inside
  # the privacy copy. Both share one template.
  def privacy
    render_legal "Privacy Policy", site_settings.privacy_policy
  end

  def terms
    render_legal "Terms of Service", site_settings.terms
  end

  # XML sitemap of the public surface for search engines.
  def sitemap
    @posts = Post.current.published.includes(:record)
    @books = Book.current.published.includes(:record)
    fresh_when etag: [ @posts, @books, site_settings ], public: true
  end

  # robots.txt — allow everything, point crawlers at the sitemap.
  def robots
    render plain: "User-agent: *\nAllow: /\n\nSitemap: #{root_url}sitemap.xml\n",
      content_type: "text/plain"
  end

  private
    def render_legal(title, body)
      @title, @body = title, body
      fresh_when etag: site_settings, public: true
      render :legal
    end
end
