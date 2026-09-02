# Container↔book membership as a resource, added/removed live from the typeahead
# on either page. The container is a Series or a Collection; create links a book
# to it (appending it to that container's order) and streams back the appropriate
# chip or row (keyed by `context`); destroy unlinks. You may link/unlink if you
# can manage either side.
class Admin::InstallmentsController < Admin::BaseController
  CONTAINER_TYPES = %w[ Series Collection ].freeze

  def create
    @container_record = Current.account.records.active.where(recordable_type: CONTAINER_TYPES).find(params[:container_record_id])
    @book_record      = Current.account.records.active.books.find(params[:book_record_id])
    authorize_membership!(@container_record, @book_record)
    @context = params[:context]

    @installment = Installment.where(container_record_id: @container_record.id, book_record_id: @book_record.id)
      .first_or_create! do |installment|
        installment.position = (Installment.where(container_record_id: @container_record.id).maximum(:position) || 0) + 1
      end
  end

  def destroy
    @installment = Installment.find(params[:id])
    authorize_membership!(Current.account.records.find(@installment.container_record_id), Current.account.records.find(@installment.book_record_id))
    @installment.destroy
    render turbo_stream: turbo_stream.remove(helpers.dom_id(@installment))
  end

  private
    def authorize_membership!(container_record, book_record)
      return if allowed_to?(:manage, container_record) || allowed_to?(:manage, book_record)
      raise ApplicationPolicy::NotAuthorizedError
    end
end
