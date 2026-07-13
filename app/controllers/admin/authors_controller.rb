# Managing the public pen names — recordables on the spine, but always-live and
# edited in place (no draft/publish). Domain-admin only. Content creators just
# *select* an author on the composer; curating the personas is the admin's job.
class Admin::AuthorsController < Admin::BaseController
  before_action :set_author, only: %i[edit update destroy]

  def index
    @authors = Author.current.ordered.includes(:record)
  end

  def new
    @author = Author.new
  end

  def create
    @author = Author.new(author_params)

    if @author.valid?
      Record.originate(@author)
      # Straight to edit so the avatar well (its own resource) is available.
      redirect_to edit_admin_author_path(@author.record), notice: "Author added — add a picture below."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Mutable persona: edits update the current version in place, no new row.
  def update
    if @author.update(author_params)
      redirect_to admin_authors_path, notice: "Author saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Trash the persona (recoverable). The author_record_id on content that used it
  # simply goes stale and the byline falls back to the account holder.
  def destroy
    @record.trash
    redirect_to admin_authors_path, notice: "Author removed."
  end

  private
    def set_author
      @record = Record.active.authors.find(params[:id])
      @author = @record.recordable
    end

    def author_params
      params.expect(author: [ :name, :bio, :default ])
    end
end
