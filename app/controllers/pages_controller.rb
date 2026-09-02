# Public-facing Merovex Press pages (the front of house). Anonymous — no session
# required — and rendered in the standalone "public" layout rather than the
# Inkwell admin chrome.
class PagesController < PublicController
  def home
    # Books for the home-page scroller: series order first (books within a
    # series by release date), then standalone titles by release date. A book
    # in multiple series appears once.
    linked = Installment.select(:book_record_id)
    in_series = Current.account.series.published.feed_ordered.flat_map do |series|
      series.books.published.reorder(:publication_date).to_a
    end
    standalone = Current.account.books.published.where.not(record_id: linked)
      .includes(:record, :depiction).order(:publication_date)
    @scroller_books = (in_series + standalone).uniq(&:record_id)
    fresh_when etag: [ @scroller_books, site_settings ], public: true
  end

  # The standing pages, authored at /admin/pages as Pages on the spine. An
  # unpublished page reads as an empty one out here — site_page only answers
  # for live ones.
  def about
    @page = site_page("about")
    fresh_when etag: [ @page, site_settings ], public: true
  end

  # Legal pages (cookies live inside the privacy copy) share one template.
  def privacy
    render_legal site_page("privacy"), "Privacy Policy"
  end

  def terms
    render_legal site_page("terms"), "Terms of Service"
  end

  # XML sitemap of the public surface for search engines.
  def sitemap
    @posts = Current.account.posts.published.includes(:record)
    @books = Current.account.books.published.includes(:record)
    fresh_when etag: [ @posts, @books, site_settings, site_page("privacy"), site_page("terms") ], public: true
  end

  # robots.txt — allow everything, point crawlers at the sitemap.
  def robots
    render plain: "User-agent: *\nAllow: /\n\nSitemap: #{root_url}sitemap.xml\n",
      content_type: "text/plain"
  end

  private
    # The author may retitle the page; the fallback covers an account whose
    # pages predate the seeding and were never backfilled.
    def render_legal(page, fallback_title)
      @title = page&.title.presence || fallback_title
      @body = page&.content
      render :legal if stale?(etag: [ page, site_settings ], public: true)
    end
end
