# Public-facing blog: the published-posts index (/blog) and the individual
# article page (/blog/:id, where :id is the Record id — the stable public
# identity). Anonymous and rendered in the public Merovex Press layout. Only
# published, untrashed posts are ever exposed here; drafts and scheduled work
# stay in the Inkwell backend.
class BlogController < PublicController
  def index
    @posts = Post.current.published
      .includes(record: :creator, body: :rich_text_content)
      .feed_ordered
    fresh_when etag: [ @posts, site_settings ], public: true
  end

  # RSS 2.0 of the latest published posts (footer + feed readers).
  def feed
    @posts = Post.current.published
      .includes(record: :creator, body: :rich_text_content)
      .feed_ordered.limit(20)
    fresh_when etag: [ @posts, site_settings ], public: true
  end

  # :id is the id-first slug ("3-my-title"). Record.find keys on the leading
  # integer (String#to_i drops the tail), so a stale or bare-id slug still
  # resolves — we 301 it to the canonical slug to keep one URL per article.
  #
  # A scheduled post is reachable early only through its full keyed slug (the
  # #preview_key segment); the bare id 404s. It's noindexed until it publishes,
  # at which point the key drops and the old keyed link 301s to the clean slug.
  # This lets a broadcast go out before publish without a dead "view on the web"
  # link.
  def show
    @record = find_public_record(Post)
    @post = @record.recordable

    if @post.published?
      return redirect_to blog_post_path(@record.to_slug), status: :moved_permanently unless canonical_slug?
      # Anonymous + only changes on a new version → cache at the edge; the etag
      # also folds in site identity so a Setting change busts it.
      fresh_when etag: [ @record, site_settings ], public: true
    elsif @post.scheduled? && canonical_slug?
      # Early-access preview: keep it out of search and out of any shared cache.
      response.set_header("X-Robots-Tag", "noindex")
      response.headers["Cache-Control"] = "no-store"
    else
      raise ActiveRecord::RecordNotFound
    end
  end
end
