class Admin::BooksController < ApplicationController
  include BookScoped, Publishing
  skip_before_action :set_record, only: %i[index new create search]
  before_action -> { authorize! @record, to: :view }, only: :show
  before_action -> { authorize! @record, to: :manage }, only: %i[edit update destroy]

  def index
    @books = Book.current.includes(:record, :creator, :depiction, body: :rich_text_content).feed_ordered
  end

  def show
  end

  def new
    @book = Book.new
  end

  def create
    @book = Book.new(book_params.merge(event: :created, status: initial_status,
      published_at: (Time.current if publishing?)))

    @book.valid?
    if scheduling? && !scheduled_at&.future?
      @book.errors.add(:base, "That scheduled time has already passed — pick a later one.")
    end

    if @book.errors.none?
      Record.originate(@book)
      @book.schedule(at: scheduled_at) if scheduling?
      redirect_to admin_book_path(@book.record), notice: create_notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @book = @record.save_edit(**book_params.to_h.symbolize_keys,
      publish: publishing?, schedule_at: (scheduled_at if scheduling?), unschedule: unscheduling?)

    if @book.errors.none?
      redirect_to admin_book_path(@record)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.trash
    redirect_to admin_books_path, notice: "Book moved to trash."
  end

  # Typeahead results for the "add a book" combobox on a series page: current
  # books matching the query, excluding ones already in that series.
  def search
    render partial: "admin/installments/results", locals: { results: matching_books }, layout: false
  end

  private
    def book_params
      params.expect(book: [ :title, :content, :publication_date ])
    end

    # Current books matching ?q=, minus any already linked to ?series_record_id.
    def matching_books
      q = params[:q].to_s.strip
      return Book.none if q.blank?

      scope = Book.current.where("title LIKE ?", "%#{Book.sanitize_sql_like(q)}%").order(:title).limit(10)
      if params[:series_record_id].present?
        scope = scope.where.not(record_id: Installment.where(series_record_id: params[:series_record_id]).select(:book_record_id))
      end
      scope
    end

    def create_notice
      if scheduling?
        "Book scheduled for #{scheduled_at.strftime('%b %-d at %H:%M')}."
      elsif publishing?
        "Book published."
      else
        "Draft saved."
      end
    end
end
