# Public-facing book catalog. The index lists published books grouped by their
# series (plus any standalone titles); the show page is an individual book.
# Anonymous, rendered in the public Merovex Press layout. Only published,
# untrashed books are exposed here.
class BooksController < PublicController
  def index
    @series = Series.current.published.includes(:record).feed_ordered.filter_map do |series|
      books = series.books.select(&:published?)
      [ series, books ] if books.any?
    end

    linked = Installment.select(:book_record_id)
    @standalone = Book.current.published.where.not(record_id: linked)
      .includes(:record, :depiction).order(:publication_date)
  end

  def show
    @record = Record.active.find(params[:id])
    @book = @record.recordable
    raise ActiveRecord::RecordNotFound unless @book.is_a?(Book) && @book.published?

    if params[:id] != @record.to_slug
      redirect_to book_path(@record.to_slug), status: :moved_permanently
    end
  end
end
