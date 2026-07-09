# Public-facing book catalog. The index lists published books grouped by their
# series (plus any standalone titles); the show page is an individual book.
# Anonymous, rendered in the public Merovex Press layout. Only published,
# untrashed books are exposed here.
class BooksController < PublicController
  def index
    @series = Series.current.published.includes(:record).feed_ordered.filter_map do |series|
      books = series.books.published
      [ series, books ] if books.any?
    end

    linked = Installment.select(:book_record_id)
    @standalone = Book.current.published.where.not(record_id: linked)
      .includes(:record, :depiction).order(:publication_date)
  end

  def show
    @record = find_public_record(Book)
    @book = @record.recordable
    raise ActiveRecord::RecordNotFound unless @book.published?

    return redirect_to book_path(@record.to_slug), status: :moved_permanently unless canonical_slug?
    fresh_when etag: [ @record, site_settings ], public: true
  end
end
