# Everything an author wrote, walked once into plain hashes — the payload of
# content.json, and the one source the archive's HTML pages and wordpress.xml
# are both rendered from, so the three can't disagree.
#
# Scope is "all but trash": published, drafted, scheduled, and archived
# records (account.posts et al. start from records.active). Bodies pass
# through Exporter::Prose; every image lands in the archive's media/ folder
# via the block given to #initialize, which stores a blob and returns the
# archive-relative path.
class Export::Content
  FORMAT_VERSION = 1

  def initialize(account, &store)
    @account = account
    @store = store
    @prose = Exporter::Prose.new(&store)
  end

  def to_h
    @to_h ||= {
      format: "inkwell-export",
      format_version: FORMAT_VERSION,
      exported_at: Time.current.iso8601,
      site: site,
      authors: authors,
      posts: posts,
      pages: pages,
      books: books,
      series: account.series.feed_ordered.map { |series| shelf(series) },
      collections: account.collections.feed_ordered.map { |collection| shelf(collection) },
      drips: drips
    }
  end

  private
    attr_reader :account

    def site
      { name: account.site.site_name, tagline: account.site.tagline, url: site_url,
        logo: image(account.site.logo) }
    end

    def site_url = "https://#{account.public_address}/"

    def authors
      account.authors.ordered.map do |author|
        { id: author.record_id, name: author.name, tagline: author.tagline, default: author.default,
          bio_html: html(author.bio), avatar: image(author.avatar) }
      end
    end

    # body_html is what the site shows; the tip-in (newsletter-only prose)
    # rides beside it, and newsletter.body_html is the two spliced together
    # exactly as subscribers received them.
    def posts
      account.posts.feed_ordered.includes(:record).map do |post|
        publishable(post).merge(
          url: public_url("posts", post),
          byline: post.byline,
          excerpt: post.excerpt,
          body_html: html(post.public_content),
          tipin_html: html(post.tipin),
          newsletter: newsletter(post)
        )
      end
    end

    def newsletter(post)
      return unless broadcast = post.record.broadcast

      { state: broadcast.state, sent_at: broadcast.sent_at&.iso8601, scheduled_at: broadcast.scheduled_at&.iso8601,
        body_html: html(post.email_content),
        recipients: broadcast.recipients_count, delivered: broadcast.delivered_count,
        opened: broadcast.opened_count, clicked: broadcast.clicked_count,
        bounced: broadcast.bounced_count, complained: broadcast.complained_count,
        unsubscribed: broadcast.unsubscribed_count }
    end

    def pages
      account.pages.joins(:record).order("records.slug").includes(:record).map do |page|
        publishable(page).merge(url: ("#{site_url}#{page.slug}/" if page.published?), body_html: html(page.content))
      end
    end

    def books
      account.books.feed_ordered.includes(:record, :depiction).map do |book|
        publishable(book).merge(
          url: public_url("books", book),
          byline: book.byline,
          tagline: book.tagline,
          isbn: book.isbn,
          publication_date: book.publication_date,
          word_count: book.word_count,
          cover: (image(book.depiction.image) if book.cover?),
          description_html: html(book.content),
          distributors: distributors(book.record)
        )
      end
    end

    # Series and collections are the same shape: a titled shelf of books, in
    # shelf order, referenced by id so content.json stays normalized.
    def shelf(shelf)
      publishable(shelf).merge(
        description_html: html(shelf.content),
        book_ids: shelf.books.pluck(:record_id),
        distributors: distributors(shelf.record)
      )
    end

    # A drip is a sequence; its drops are the emails, in send order.
    def drips
      account.drips.order(:title).map do |drip|
        { id: drip.record_id, title: drip.title, active: drip.active, trigger: drip.trigger,
          drops: drip.drops.includes(:magnet).map do |drop|
            { id: drop.record_id, subject: drop.subject, delay_days: drop.delay_days, notes: drop.notes,
              magnet: drop.magnet&.title, body_html: html(drop.body) }
          end }
      end
    end

    # What every Publishable carries. id is the Record id — the stable
    # identity, and the number in the item's public slug. published_at on a
    # scheduled item is its appointment.
    def publishable(item)
      { id: item.record_id, slug: slug(item), title: item.title, status: item.status,
        archived: item.record.archived?, pinned: item.pinned_at.present?,
        created_at: item.record.created_at.iso8601, updated_at: item.updated_at.iso8601,
        published_at: item.published_at&.iso8601 }
    end

    # Record#to_slug minus the pre-publish preview key: a draft's export slug
    # is the one it will publish under. Pages carry their permanent path.
    def slug(item)
      item.record.slug.presence || [ item.record_id, item.title.parameterize.presence ].compact.join("-")
    end

    # Only what the world can actually visit has a URL.
    def public_url(section, item)
      "#{site_url}#{section}/#{slug(item)}" if item.published?
    end

    def distributors(record)
      record.distributors.map { |distributor| { name: distributor.display_name, url: distributor.url } }
    end

    def html(rich_text) = @prose.html(rich_text)

    def image(attachment)
      @store.call(attachment.blob) if attachment&.attached?
    end
end
