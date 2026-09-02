class ApplicationController < ActionController::Base
  include Authentication
  include Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Serve Action Text image attachments as WebP for the website (every visitor is
  # webp-capable per allow_browser above). Mailers have no request and so never
  # run this, leaving them email-safe (JPEG). See ApplicationHelper#attachment_variation.
  before_action { Current.web_images = true }

  # Every scoped lookup in the app (wrong id, trashed record, wrong type,
  # someone else's yours-only content) lands here: one friendly in-app 404
  # instead of an exception page, offering the way back to where they just
  # were. Probing ids is indistinguishable from a typo.
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  # Root-only surfaces (support desk, staff directory, Mission Control):
  # platform staff or a bare 404 — what exists is nobody's business but its
  # audience's. Bare head, not the friendly errors page: engine-hosted
  # surfaces (Mission Control) would render that under the wrong layout.
  def self.require_root
    before_action -> { head :not_found unless Current.user&.root? }
  end

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :hotwire_native?, :current_theme, :press_theme, :press_heading_font, :current_tint, :site_settings, :site_page

  # The account's public identity (name, tagline, logo…), memoized per request.
  # Drives the public site chrome; see the "public" layout.
  def site_settings
    @site_settings ||= Current.account.site
  end

  # A standing page (about, privacy, terms, newsletter) when it's published
  # and actually written — what the footer, sitemap, and meta description ask
  # before linking or quoting it. Memoized per request per slug.
  def site_page(slug)
    @site_pages ||= Hash.new do |pages, wanted|
      pages[wanted] = Current.account.page(wanted)&.then { |page| page if page.published? }
    end
    @site_pages[slug]
  end

  # True when the request comes from the Hotwire Native wrapper (vs. web/PWA), so
  # views can suppress web nav chrome and let native nav take over. See
  # docs/decisions/0005-mobile-hotwire-native-pwa-dev.md.
  def hotwire_native?
    request.user_agent.to_s.match?(/Hotwire Native|Turbo Native/)
  end

  # Persisted appearance prefs (set as cookies by the theme/tint Stimulus
  # controllers). Whitelisted/sanitized so they're safe to render into the
  # <html> attributes; unknown values fall back to the defaults.
  ALLOWED_THEMES = %w[light dark auto].freeze

  def current_theme
    ALLOWED_THEMES.include?(cookies[:theme]) ? cookies[:theme] : "light"
  end

  # The public site keeps its own cookie so the admin preference never bleeds
  # through — Merovex Press is dark by default.
  def press_theme
    ALLOWED_THEMES.include?(cookies[:press_theme]) ? cookies[:press_theme] : "dark"
  end

  # TEMP heading-font audition (see press-hfont.css): slugs cycled
  # alphabetically by the public nav's font button. Delete when decided.
  PRESS_HEADING_FONTS = %w[archivo-narrow].freeze

  def press_heading_font
    PRESS_HEADING_FONTS.include?(cookies[:press_hfont]) ? cookies[:press_hfont] : "archivo-narrow"
  end

  def current_tint
    cookies[:tint].to_s.match?(/\A[a-z]+(-[a-z0-9]+)?\z/) ? cookies[:tint] : "zinc"
  end

  private
    # The 404 keeps the status (probes and tests see :not_found) but leads
    # with "Go back" — url_from only admits same-origin referers, so the
    # button never sends anyone off-site; direct hits fall back to home.
    def render_not_found
      @back_url = url_from(request.referer)
      render "errors/not_found", status: :not_found, formats: :html
    end

    # The page a record's boost strip lives on, anchored to the strip: the
    # chat room for a chat line, the parent's page for a comment, else the
    # record's own page (post or message — commentable_path resolves the
    # route from the type). Boost actions redirect here and Turbo extracts
    # the strip's frame from the response, so the swap happens in place.
    def record_page_path(record)
      anchor = helpers.dom_id(record, :boosts)
      case record.recordable_type
      when "ChatLine" then admin_chatroom_path(anchor: anchor)
      when "Comment"  then helpers.commentable_path(record.parent, anchor: anchor)
      when "Beat"     then circle_pulse_path(record.bucket, record.parent_id, anchor: anchor)
      else helpers.commentable_path(record, anchor: anchor)
      end
    end
end
