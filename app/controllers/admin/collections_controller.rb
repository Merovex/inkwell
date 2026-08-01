class Admin::CollectionsController < Admin::BaseController
  include CollectionScoped, Publishing
  skip_before_action :set_record, only: %i[index new create search]
  before_action -> { authorize! @record, to: :view }, only: :show
  before_action -> { authorize! @record, to: :manage }, only: %i[edit update destroy reorder]

  def index
    @collections = Current.account.collections.includes(:record, :creator, body: :rich_text_content).feed_ordered
  end

  # The collection page lists its books in order — drag-sortable to set position.
  def show
  end

  # Typeahead results for the "add a collection" combobox on a book page: current
  # collections matching the query, excluding ones already linked to that book.
  def search
    render partial: "admin/installments/results", locals: { results: matching_collections }, layout: false
  end

  def new
    @collection = Collection.new
  end

  def create
    @collection = Collection.new(collection_params.merge(event: :created, status: initial_status,
      published_at: (Time.current if publishing?)))

    @collection.valid?
    if scheduling? && !scheduled_at&.future?
      @collection.errors.add(:base, "That scheduled time has already passed — pick a later one.")
    end

    if @collection.errors.none?
      Record.originate(@collection)
      @collection.schedule(at: scheduled_at) if scheduling?
      redirect_to admin_collection_path(@collection.record), notice: create_notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @collection = @record.save_edit(**collection_params.to_h.symbolize_keys,
      publish: publishing?, schedule_at: (scheduled_at if scheduling?), unschedule: unscheduling?)

    if @collection.errors.none?
      redirect_to admin_collection_path(@record)
    else
      @books = @collection.books
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @record.trash
    redirect_to admin_collections_path, notice: "Collection moved to trash."
  end

  # Drag-reorder the collection's books: PATCH with book_record_ids[] in the new
  # order; positions are rewritten 1..n for this collection only.
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
    # Current collections matching ?q=, minus any already linked to ?book_record_id.
    def matching_collections
      q = params[:q].to_s.strip
      return Collection.none if q.blank?

      scope = Current.account.collections.where("title LIKE ?", "%#{Collection.sanitize_sql_like(q)}%").order(:title).limit(10)
      if params[:book_record_id].present?
        scope = scope.where.not(record_id: Installment.where(book_record_id: params[:book_record_id]).select(:container_record_id))
      end
      scope
    end

    def collection_params
      params.expect(collection: [ :title, :content, :author_record_id ])
    end

    def create_notice
      if scheduling?
        "Collection scheduled for #{scheduled_at.strftime('%b %-d at %H:%M')}."
      elsif publishing?
        "Collection published."
      else
        "Draft saved."
      end
    end
end
