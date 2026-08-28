require "vips" # measured dimensions ride image_sizes.json (not only variants)

# Phase 2's exporter (docs/hugo-build-pipeline.md §4): assembles one
# account's build workspace — the versioned JSON transport that Hugo themes
# consume, the referenced image blobs, the generated hugo.toml (the one
# place Rails writes Hugo-facing config), and a symlink to the pinned
# theme. Writes a fresh workspace under BUILDS_PATH and returns its path.
# The render/publish steps belong to the Renderer/Publisher.
class Exporter
  CONTRACT_VERSION = 2

  # design is the full SiteDesign bundle (axes + content blocks + escape
  # valves), raw as the author saved it — defaults to the account's persisted
  # design, which a preview build overrides with the live, unsaved payload.
  # The axes are re-checked against the theme vocabulary here as the last gate
  # before Hugo (§6.1); custom colors resolve to per-role shades at this
  # point. base_url lets a preview render under the admin's preview path
  # prefix; preview gates designer-facing affordances only (ADR 0022 — no
  # build mode ever varies the design).
  def initialize(account, design: account.published_design&.data, base_url: "/", preview: false)
    @account = account
    @theme = Theme.current
    @design = (design || {}).with_indifferent_access
    @base_url = base_url
    @preview = preview
  end

  # A build is a snapshot of "published now" (§5.1): current versions of
  # active records, published status only.
  def export!
    write "site.json",   site_json
    write "author.json", author_json
    write "authors.json", authors_json
    write "books.json",  books_json
    write "series.json", series_json
    write "collections.json", collections_json
    write "posts.json",  posts_json
    write "pages.json",  pages_json
    # Written LAST — populated as the builders above copy images.
    write "image_sizes.json", image_sizes
    write_hugo_config
    link_theme
    workspace
  end

  private
    attr_reader :account, :theme

    def workspace
      @workspace ||= Pathname(builds_path).join(account.slug, Time.current.utc.strftime("%Y%m%d%H%M%S%L"))
    end

    # Production sets BUILDS_PATH (the /var/cache/inkwell/builds bind mount,
    # /rails/builds in-container); dev and test build under tmp/, which
    # needs no provisioning.
    def builds_path
      ENV.fetch("BUILDS_PATH") { Rails.root.join("tmp/builds").to_s }
    end

    def write(filename, payload)
      workspace.join("data").tap(&:mkpath)
        .join(filename).write(JSON.pretty_generate(payload.merge(contract_version: CONTRACT_VERSION)))
    end

    def write_hugo_config
      workspace.join("hugo.toml").write(<<~TOML)
        baseURL = #{@base_url.to_json}
        # Page-relative asset/nav URLs are for ROOT-based builds only (custom
        # domain): one build then serves correctly both at the domain root AND
        # under the platform path prefix (sites.kindredquill.com/<handle>/) —
        # the pre-domain fallback host. A path-prefixed baseURL (domain-less
        # account) must keep absolute URLs instead: Hugo relativizes against
        # the OUTPUT path, not the URL path, so relative + prefix emits a
        # doubled /<handle>/<handle>/ that 404s. Absolute .Permalink URLs
        # (canonical, OG, JSON-LD) are unaffected either way and stay pinned
        # to baseURL. NOT for preview: the designer preview is served at a
        # fixed non-directory URL that matches its base_url, where
        # page-relative URLs resolve one level too high and break.
        relativeURLs = #{URI(@base_url).path == "/" && !@preview}
        locale = "en-us"
        title = #{account.site.site_name.to_json}
        theme = #{theme.name.to_json}

        # Payload dates (books/posts) can be ahead of build time.
        buildFuture = true

        # The platform signs the page, not the tool (baseof.html emits its
        # own Kindred Quill generator meta).
        disableHugoGeneratorInject = true

        disableKinds = ["taxonomy", "term"]

        [params]
        # Designer-facing affordances only; never varies the design (ADR 0022).
        preview = #{@preview}

        # The contract delivers pre-rendered, sanitized HTML bodies.
        [security]
        allowContent = ['^text/html$', '^text/markdown$']

        # Cover images live in assets/images/ (per the contract); serve them
        # at /images/... without an asset pipeline.
        [module]
          [[module.mounts]]
            source = "assets/images"
            target = "static/images"
      TOML
    end

    def link_theme
      workspace.join("themes").tap(&:mkpath).join(theme.name).make_symlink(theme.path)
    end

    def site_json
      site = account.site
      {
        name: site.site_name,
        tagline: site.tagline,
        contact_email: account.contact_email,
        logo: copy_image(site.logo, "logo"),
        **svg_logo_extras(site),
        banner: copy_image(site.banner, "banner"),
        hero_image: copy_image(site.hero_image, "hero"),
        newsletter_photo: copy_image(site.newsletter_photo, "newsletter"),
        design: theme.defaults.merge(theme.permit!(@design[:design]))
      }.merge(content_blocks)
    end

    # The content blocks and escape valves the SiteDesigner edits — carried
    # only when set, so the theme falls back to its own defaults otherwise.
    # Colors are the exception: stored raw, resolved to per-role/mode shades
    # here (PaletteColor owns the a11y policy).
    def content_blocks
      {
        nav: @design[:nav],
        fonts: @design[:fonts],
        colors: resolve_colors(@design[:colors]),
        hero: @design[:hero],
        newsletter: newsletter_block,
        home: { sections: @design[:sections].presence,
                headings: @design[:headings].presence }.compact_blank.presence
      }.compact_blank
    end

    # The newsletter band's signup wiring (bot-protection plan §3): the theme
    # renders a real form only when the account can actually send the
    # confirmation email; otherwise it keeps its mailto fallback. provider
    # names the theme partial that renders the form (ses-newsletter today;
    # mailchimp etc. slot in beside it later). The honeypot field name is the
    # shared Subscriber constant so the baked form and the server can never
    # drift. The island-auth secret is deliberately NOT here — nothing secret
    # rides baked HTML.
    def newsletter_block
      block = (@design[:newsletter] || {}).to_h
      if account.ses_tenant_provisioned?
        block = block.merge(signup: {
          enabled: true,
          provider: "ses",
          honeypot_field: Subscriber::HONEYPOT_FIELD,
          turnstile_sitekey: TurnstileVerifier.site_key_for(account)
        }.compact_blank)
      end
      block.presence
    end

    def resolve_colors(colors)
      return nil if colors.blank?

      colors.to_h { |role, hex| [ role, PaletteColor.resolve(role, hex) ] }
    end

    # The default pen-name persona; an account that never created one falls
    # back to the owner's name, matching Authored#byline.
    def author_json
      if author = account.authors.find_by(default: true) || account.authors.first
        { name: author.name, slug: author.name.parameterize, tagline: author.tagline,
          bio_html: html(author.bio), avatar: copy_image(author.avatar, "author"),
          hero_image: copy_image(author.hero_image, "author-hero") }
      else
        { name: account.owner.display_name, slug: account.owner.display_name.parameterize,
          tagline: nil, bio_html: nil, avatar: nil, hero_image: nil }
      end
    end

    # Every current pen name, for the author-grid section (data-authors=yes).
    # Name-based slug and avatar prefix keep the transport deterministic (§2)
    # and match the public /authors/<slug>/ pages.
    def authors_json
      { authors: account.authors.ordered.map do |author|
          { name: author.name, slug: author.public_slug, tagline: author.tagline,
            bio_html: html(author.bio), avatar: copy_image(author.avatar, "author-#{author.public_slug}") }
        end }
    end

    def books_json
      { books: account.books.published.feed_ordered.map do |book|
          placement = series_placement(book)
          {
            slug: book.record.to_slug,
            title: book.title,
            series_slug: placement&.first,
            position: placement&.last,
            publication_date: book.publication_date,
            cover: book.cover? ? copy_image(book.depiction.image, book.record_id) : nil,
            description_html: html(book.content),
            distributors: distributors_for(book.record)
          }
        end }
    end

    # Series and collections are the same shape: a titled shelf of published
    # books, with their own buy-links (authors may point at a whole shelf rather
    # than each book — the links hang on the shelf's Record either way).
    def series_json
      { series: account.series.published.feed_ordered.map { |series| shelf_json(series) } }
    end

    def collections_json
      { collections: account.collections.published.feed_ordered.map { |collection| shelf_json(collection) } }
    end

    def shelf_json(shelf)
      {
        slug: shelf.record.to_slug,
        title: shelf.title,
        description_html: html(shelf.content),
        books: shelf.books.published.map { |book| book.record.to_slug },
        distributors: distributors_for(shelf.record)
      }
    end

    # The standing pages (About, Privacy, Terms, the newsletter invitation) —
    # published ones only, ordered by slug so the transport is byte-stable
    # across builds (§2). The theme materializes one page per entry at the
    # site root; /newsletter/ is the one whose body rides above the signup
    # band rather than standing alone.
    def pages_json
      { pages: account.pages.published.joins(:record).order("records.slug")
          .includes(:record, body: :rich_text_content).map do |page|
            { slug: page.slug, title: page.title, body_html: html(page.content) }
          end }
    end

    def posts_json
      { posts: account.posts.published.feed_ordered.map do |post|
          {
            slug: post.record.to_slug,
            title: post.title,
            published_at: post.published_at&.iso8601,
            byline: post.byline,
            excerpt: post.summary,
            body_html: html(post.content)
          }
        end }
    end

    # A book's shelf position: the first installment whose series is live and
    # published — [series slug, position], or nil for a standalone book.
    def series_placement(book)
      book.installments.order(:position).each do |installment|
        series = Series.current.published.find_by(record_id: installment.container_record_id)
        return [ series.record.to_slug, installment.position ] if series
      end
      nil
    end

    def distributors_for(record)
      record.distributors.map do |distributor|
        { name: distributor.display_name, url: distributor.url, track_id: distributor.id }
      end
    end

    # Rendered rich text as an HTML string, stripped of dev's template
    # annotation comments (Body::TEMPLATE_ANNOTATION) — the transport must be
    # byte-identical across environments (§2 deterministic builds). User
    # content can't collide: the sanitizer already strips comments from rich
    # text.
    def html(rich_text)
      # Cleared rich text still renders its ActionText wrapper div, which is
      # emphatically not "no content": the theme decides whether to link a
      # legal page or render a prose block by asking whether the HTML is
      # empty, so blank has to arrive as blank.
      return "" if rich_text.blank?

      localize_attachments(rich_text.to_s.gsub(Body::TEMPLATE_ANNOTATION, ""))
    end

    # Rich text carries its images as ActionText attachments, rendered with
    # ActiveStorage URLs that point back at the Rails app — a static site
    # can't serve those, and a reader hot-linking the app is not what a
    # published build means. So every image attachment is copied into the
    # workspace like any cover or logo, and its <img> is repointed at the
    # copy.
    #
    # The <action-text-attachment> wrapper is unwrapped on the way out: it's a
    # custom element with no styling anywhere but the composer, and browsers
    # lay it out inline, which boxes the figure wrongly. What ships is plain
    # <figure><img></figure>.
    #
    # Untouched: mentions and other non-blob attachables (they carry their own
    # inline HTML), and non-image blobs — a PDF in a body would need a place
    # to live on the static host, which is a separate decision.
    def localize_attachments(html)
      return html unless html.include?("action-text-attachment")

      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css("action-text-attachment[sgid]").each do |node|
        blob = attachment_blob(node)
        next unless blob&.image?

        repoint(node, copy_blob(blob, "inline-#{blob.id}"))
        # ActionText captions the file with its name and byte size when the
        # author didn't write one. That's composer chrome, not prose.
        node.css("figcaption").remove if node["caption"].blank?
        node.replace(node.children)
      end
      fragment.to_html
    end

    def attachment_blob(node)
      attachable = ActionText::Attachable.from_attachable_sgid(node["sgid"])
      attachable if attachable.is_a?(ActiveStorage::Blob)
    rescue ActiveRecord::RecordNotFound, ActiveSupport::MessageVerifier::InvalidSignature => error
      Rails.logger.warn("[exporter] unresolvable attachment in body: #{error.message}")
      nil
    end

    # Repoint the attachment's <img> at the exported copy, and stamp the
    # measured dimensions the theme's img partial would have supplied — an
    # inline image is raw HTML in the body, so nothing else can reserve its
    # layout space (the CLS fix, same as image_sizes.json).
    def repoint(node, path)
      width, height = image_sizes[path]
      node.css("img").each do |img|
        img["src"] = path
        img.remove_attribute("srcset")
        img["width"], img["height"] = width, height if width
      end
    end

    # No public display needs more than this; authors upload raw camera/stock
    # files (the merovex hero banner shipped at 491KB before the cap).
    IMAGE_LIMIT = [ 1920, 1920 ].freeze
    # Banners render behind the hero scrim, so they take a far harder squeeze —
    # noisy stock photography (starfields!) barely compresses at display quality.
    BANNER_LIMIT = [ 1280, 1280 ].freeze

    # Pulls a blob into assets/images/ and returns its workspace-relative
    # path (the form the contract's cover/avatar fields carry), nil if absent.
    # Raster images are capped to IMAGE_LIMIT and transcoded to WebP —
    # preserving the source format backfires (vips re-encodes AVIF far larger
    # than the original). Non-variable blobs (SVG) and any processing failure
    # fall back to the raw bytes — a fat image beats a broken build.
    def copy_image(attachment, prefix)
      return nil unless attachment&.attached?

      copy_blob(attachment.blob, prefix)
    end

    # A currentColor-tintable SVG logo ships as a data: URI mask plus its
    # aspect ratio (a mask box can't size itself from the file) — the theme's
    # fk-brand-logo-tint reads both. A data: URI on purpose: an inline-style
    # url() dodges Hugo's relativeURLs rewriting, which only touches
    # href/src, so a file path here would break on one of the two mounts
    # (domain root vs path prefix). Raster logos carry no extras.
    def svg_logo_extras(site)
      return {} unless site.logo_svg?

      bytes = site.logo.download
      extras = { logo_mask: "data:image/svg+xml;base64,#{Base64.strict_encode64(bytes)}" }
      ratio = Svg.aspect_ratio(bytes)
      ratio ? extras.merge(logo_ratio: ratio) : extras
    end

    # The workspace copy of one blob, at the contract path the theme reads
    # (images/<prefix>-<name>). Inline body images come through here too, with
    # the blob id in their prefix so two photos that share a filename can't
    # overwrite each other.
    def copy_blob(blob, prefix)
      bytes, ext = image_payload(blob, prefix)
      filename = "#{prefix}-#{File.basename(blob.filename.sanitized, '.*')}#{ext}"
      workspace.join("assets/images").tap(&:mkpath).join(filename).binwrite(bytes)
      "images/#{filename}".tap { |path| measure(path, bytes) }
    end

    # Pixel dimensions of every exported image, keyed by contract path — the
    # theme's img partial stamps them as width/height attributes so the browser
    # reserves layout space before the file arrives (the CLS fix). Unreadable
    # buffers (SVG) just aren't measured; the attributes are omitted.
    def image_sizes
      @image_sizes ||= {}
    end

    def measure(path, bytes)
      image = Vips::Image.new_from_buffer(bytes, "")
      image_sizes[path] = [ image.width, image.height ]
    rescue Vips::Error
      nil
    end

    def image_payload(blob, prefix)
      original_ext = File.extname(blob.filename.sanitized)
      return [ blob.download, original_ext ] unless blob.variable?
      limit, quality = prefix == "banner" ? [ BANNER_LIMIT, 55 ] : [ IMAGE_LIMIT, 72 ]
      variant = blob.variant(resize_to_limit: limit, format: :webp, saver: { quality: quality })
      [ variant.processed.download, ".webp" ]
    rescue ActiveStorage::Error, ActiveStorage::FileNotFoundError => error
      Rails.logger.warn("[exporter] variant failed for #{blob.filename}: #{error.message}")
      [ blob.download, original_ext ]
    end
end
