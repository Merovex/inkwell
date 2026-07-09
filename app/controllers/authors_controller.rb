# Public author persona page: bio + the published posts and books they're the
# byline on. Anonymous, edge-cacheable like the rest of the public site. :id is
# the Record id-first slug, matching the blog/books pages.
class AuthorsController < PublicController
  def show
    @record = Record.active.authors.find(params[:id])
    @author = @record.recordable
    return redirect_to author_page_path(@author), status: :moved_permanently if params[:id] != @record.to_slug

    @posts = Post.current.published.where(author_record_id: @record.id)
      .includes(record: :creator, body: :rich_text_content).feed_ordered
    @books = Book.current.published.where(author_record_id: @record.id)
      .includes(:record, :depiction).feed_ordered

    fresh_when etag: [ @record, @posts, @books, site_settings ], public: true
  end
end
