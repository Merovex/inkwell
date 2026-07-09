# Public-facing Merovex Press pages (the front of house). Anonymous — no session
# required — and rendered in the standalone "public" layout rather than the
# Inkwell admin chrome. Static for now; links are placeholders (#) until the
# real destinations exist.
class PagesController < PublicController
  def home
  end

  # Renders the About blurb an admin sets in System settings (Setting#description).
  def about
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

  private
    def render_legal(title, body)
      @title, @body = title, body
      fresh_when etag: site_settings, public: true
      render :legal
    end
end
