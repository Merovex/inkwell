require "vips" # measured dimensions ride image_sizes.json (not only variants)

# Phase 2's exporter (docs/hugo-build-pipeline.md §4): assembles one
# account's build workspace — the versioned JSON transport that Hugo themes
# consume, the referenced image blobs, the generated hugo.toml (the one
# place Rails writes Hugo-facing config), and a symlink to the pinned
# theme. Writes a fresh workspace under BUILDS_PATH and returns its path.
# The render/publish steps belong to the Renderer/Publisher.
class Exporter
  CONTRACT_VERSION = 1

  # design is the full SiteDesign bundle (axes + content blocks + escape
  # valves), raw as the author saved it — defaults to the account's persisted
  # design, which a preview build overrides with the live, unsaved payload.
  # The axes are re-checked against the theme vocabulary here as the last gate
  # before Hugo (§6.1); custom colors resolve to per-role shades at this
  # point. base_url lets a preview render under the admin's preview path
  # prefix; preview gates designer-facing affordances only (ADR 0022 — no
  # build mode ever varies the design).
  def initialize(account, design: account.design, base_url: "/", preview: false)
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
        description_html: html(site.description),
        logo: copy_image(site.logo, "logo"),
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
        home: @design[:sections].present? ? { sections: @design[:sections] } : nil
      }.compact_blank
    end

    # The newsletter band's signup wiring (bot-protection plan §3): the theme
    # renders a real form only when the account can actually send the
    # confirmation email; otherwise it keeps its mailto fallback. The honeypot
    # field name is the shared Subscriber constant so the baked form and the
    # server can never drift. The island-auth secret is deliberately NOT here —
    # nothing secret rides baked HTML.
    def newsletter_block
      block = (@design[:newsletter] || {}).to_h
      if account.ses_tenant_provisioned?
        block = block.merge(signup: {
          enabled: true,
          honeypot_field: Subscriber::HONEYPOT_FIELD,
          turnstile_sitekey: TurnstileVerifier.site_key
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
    # annotation comments — the transport must be byte-identical across
    # environments (§2 deterministic builds). User content can't collide:
    # the sanitizer already strips comments from rich text.
    def html(rich_text)
      rich_text&.to_s&.gsub(/<!-- (?:BEGIN|END) [^>]*-->\n?/m, "")
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

      bytes, ext = image_payload(attachment, prefix)
      filename = "#{prefix}-#{File.basename(attachment.blob.filename.sanitized, '.*')}#{ext}"
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

    def image_payload(attachment, prefix)
      original_ext = File.extname(attachment.blob.filename.sanitized)
      return [ attachment.blob.download, original_ext ] unless attachment.blob.variable?
      limit, quality = prefix == "banner" ? [ BANNER_LIMIT, 55 ] : [ IMAGE_LIMIT, 72 ]
      variant = attachment.variant(resize_to_limit: limit, format: :webp, saver: { quality: quality })
      [ variant.processed.download, ".webp" ]
    rescue ActiveStorage::Error, ActiveStorage::FileNotFoundError => error
      Rails.logger.warn("[exporter] variant failed for #{attachment.blob.filename}: #{error.message}")
      [ attachment.blob.download, original_ext ]
    end
end
