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
  end

  # :id is the id-first slug ("3-my-title"). Record.find keys on the leading
  # integer (String#to_i drops the tail), so a stale or bare-id slug still
  # resolves — we 301 it to the canonical slug to keep one URL per article.
  def show
    @record = Record.active.find(params[:id])
    @post = @record.recordable
    raise ActiveRecord::RecordNotFound unless @post.is_a?(Post) && @post.published?

    if params[:id] != @record.to_slug
      redirect_to blog_post_path(@record.to_slug), status: :moved_permanently
    end
  end
end
