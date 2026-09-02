class Admin::SeriesController < Admin::BaseController
  include SeriesScoped, Publishing
  skip_before_action :set_record, only: %i[index new create search]
  before_action -> { authorize! @record, to: :view }, only: :show
  before_action -> { authorize! @record, to: :manage }, only: %i[edit update destroy reorder]

  def index
    @series = Current.account.series.includes(:record, :creator, body: :rich_text_content).feed_ordered
  end

  # The series page lists its books in order — drag-sortable to set position.
  def show
  end

  # Typeahead results for the "add a series" combobox on a book page: current
  # series matching the query, excluding ones already linked to that book.
  def search
    render partial: "admin/installments/results", locals: { results: matching_series }, layout: false
  end

  def new
    @series = Series.new
  end

  def create
    @series = Series.new(series_params.merge(event: :created, status: initial_status,
      published_at: (Time.current if publishing?)))

    @series.valid?
    if scheduling? && !scheduled_at&.future?
      @series.errors.add(:base, "That scheduled time has already passed — pick a later one.")
    end

    if @series.errors.none?
      Record.originate(@series)
      @series.schedule(at: scheduled_at) if scheduling?
      # Created from the books-index modal — land back there to add its books.
      redirect_to admin_books_path, notice: create_notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @series = @record.save_edit(**series_params.to_h.symbolize_keys,
      publish: publishing?, schedule_at: (scheduled_at if scheduling?), unschedule: unscheduling?)

    if @series.errors.none?
      # Management lives on the books index now, so the modal returns there.
      redirect_to admin_books_path, notice: "Series saved."
    else
      @books = @series.books
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.trash
    redirect_to admin_books_path, notice: "Series moved to trash."
  end

  # Drag-reorder the series' books: PATCH with book_record_ids[] in the new
  # order; positions are rewritten 1..n for this series only.
  def reorder
    ids = Array(params[:book_record_ids]).map(&:to_i)
    Installment.transaction do
      ids.each_with_index do |book_record_id, i|
        Installment.where(container_record_id: @record.id, book_record_id: book_record_id)
          .update_all(position: i + 1)
      end
    end
    head :no_content
  end

  private
    # Current series matching ?q=, minus any already linked to ?book_record_id.
    def matching_series
      q = params[:q].to_s.strip
      return Series.none if q.blank?

      scope = Current.account.series.where("title LIKE ?", "%#{Series.sanitize_sql_like(q)}%").order(:title).limit(10)
      if params[:book_record_id].present?
        scope = scope.where.not(record_id: Installment.where(book_record_id: params[:book_record_id]).select(:container_record_id))
      end
      scope
    end

    def series_params
      params.expect(series: [ :title, :content, :author_record_id, :state ])
    end

    def create_notice
      if scheduling?
        "Series scheduled for #{scheduled_at.strftime('%b %-d at %H:%M')}."
      elsif publishing?
        "Series published."
      else
        "Draft saved."
      end
    end
end
