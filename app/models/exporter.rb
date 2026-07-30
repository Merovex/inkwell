# Phase 2's exporter (docs/hugo-build-pipeline.md §4): serializes one
# account's published content to the versioned JSON transport that Hugo
# themes consume, plus the referenced image blobs. Writes a fresh build
# workspace under BUILDS_PATH — the /var/cache/inkwell/builds bind mount,
# /rails/builds inside the container — and returns its path. hugo.toml
# generation and the render/publish steps belong to the Renderer/Publisher.
class Exporter
  CONTRACT_VERSION = 1

  # No theme ships an axes.yml manifest yet (§6.1), so every export defaults
  # to the first option of each design axis.
  DESIGN_DEFAULTS = {
    palette: "nebula",
    cards: "spread",
    hero: "split",
    font: "epic",
    avatar: "frame",
    avatar_side: "left",
    newsletter: "photo"
  }.freeze

  def initialize(account)
    @account = account
  end

  # A build is a snapshot of "published now" (§5.1): current versions of
  # active records, published status only.
  def export!
    write "site.json",   site_json
    write "author.json", author_json
    write "books.json",  books_json
    write "series.json", series_json
    write "posts.json",  posts_json
    workspace
  end

  private
    attr_reader :account

    def workspace
      @workspace ||= Pathname(ENV.fetch("BUILDS_PATH", "/var/cache/inkwell/builds"))
        .join(account.slug, Time.current.utc.strftime("%Y%m%d%H%M%S%L"))
    end

    def write(filename, payload)
      workspace.join("data").tap(&:mkpath)
        .join(filename).write(JSON.pretty_generate(payload.merge(contract_version: CONTRACT_VERSION)))
    end

    def site_json
      site = account.site
      {
        name: site.site_name,
        tagline: site.tagline,
        contact_email: account.contact_email,
        description_html: html(site.description),
        design: DESIGN_DEFAULTS
      }
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
