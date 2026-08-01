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
    write "books.json",  books_json
    write "series.json", series_json
    write "posts.json",  posts_json
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
        newsletter: @design[:newsletter],
        home: @design[:sections].present? ? { sections: @design[:sections] } : nil
      }.compact_blank
    end

    def resolve_colors(colors)
      return nil if colors.blank?

      colors.to_h { |role, hex| [ role, PaletteColor.resolve(role, hex) ] }
    end

    # The default pen-name persona; an account that never created one falls
    # back to the owner's name, matching Authored#byline.
    def author_json
      if author = account.authors.find_by(default: true) || account.authors.first
        { name: author.name, slug: author.name.parameterize,
          bio_html: html(author.bio), avatar: copy_image(author.avatar, "author") }
      else
        { name: account.owner.display_name, slug: account.owner.display_name.parameterize,
          bio_html: nil, avatar: nil }
      end
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
            distributors: book.record.distributors.map do |distributor|
              { name: distributor.display_name, url: distributor.url, track_id: distributor.id }
            end
          }
        end }
    end

    def series_json
      { series: account.series.published.feed_ordered.map do |series|
          {
            slug: series.record.to_slug,
            title: series.title,
            description_html: html(series.content),
            books: series.books.published.map { |book| book.record.to_slug }
          }
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
        series = Series.current.published.find_by(record_id: installment.series_record_id)
        return [ series.record.to_slug, installment.position ] if series
      end
      nil
    end

    # Rendered rich text as an HTML string, stripped of dev's template
    # annotation comments — the transport must be byte-identical across
    # environments (§2 deterministic builds). User content can't collide:
    # the sanitizer already strips comments from rich text.
    def html(rich_text)
      rich_text&.to_s&.gsub(/<!-- (?:BEGIN|END) [^>]*-->\n?/m, "")
    end

    # Pulls a blob into assets/images/ and returns its workspace-relative
    # path (the form the contract's cover/avatar fields carry), nil if absent.
    def copy_image(attachment, prefix)
      return nil unless attachment&.attached?

      filename = "#{prefix}-#{attachment.blob.filename.sanitized}"
      workspace.join("assets/images").tap(&:mkpath)
        .join(filename).binwrite(attachment.blob.download)
      "images/#{filename}"
    end
end
