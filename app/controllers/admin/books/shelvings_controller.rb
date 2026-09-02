# Moving a book from one series to another (or to standalone) — the "Move to
# another series" picker (8b) opened over the book page. The book's placement is
# the series Installment; create reassigns it and renumbers both series.
class Admin::Books::ShelvingsController < Admin::BaseController
  include BookScoped
  before_action -> { authorize! @record, to: :manage }

  def new
    @series = Current.account.series.feed_ordered
    @current_series = @book.series.first
  end

  def create
    target = params[:container_record_id].presence
    if target && !Current.account.series.exists?(record_id: target)
      redirect_to admin_book_path(@record), alert: "That series is no longer available."
    else
      @book.shelve_in_series(target)
      redirect_to admin_book_path(@record), notice: "Book moved."
    end
  end
end
