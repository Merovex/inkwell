# Public author persona page: bio + the published posts and books they're the
# byline on. Anonymous, edge-cacheable like the rest of the public site. :id is
# the pretty name slug (/authors/troy-buzby); legacy id-first slugs 301 to it.
class AuthorsController < PublicController
  def show
    @author = find_author
    @record = @author.record
    return redirect_to author_page_path(@author.public_slug), status: :moved_permanently if params[:id] != @author.public_slug

    @posts = Post.current.published.where(author_record_id: @record.id)
      .includes(record: :creator, body: :rich_text_content).feed_ordered
    @books = Book.current.published.where(author_record_id: @record.id)
      .includes(:record, :depiction).feed_ordered

    fresh_when etag: [ @record, @posts, @books, site_settings ], public: true
  end

  private
    # Canonical lookup is by name slug; a leading-integer slug (the old id-first
    # form) still resolves via the Record spine so shared links don't die.
    def find_author
      Author.current.detect { |author| author.public_slug == params[:id] } ||
        Record.active.authors.find(params[:id]).recordable
    end
end
