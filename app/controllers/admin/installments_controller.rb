# Series↔book membership as a resource, added/removed live from the typeahead
# on either page. create links a book to a series (appending it to that series'
# order) and streams back the appropriate chip (book page) or row (series page);
# destroy unlinks. You may link/unlink if you can manage either side.
class Admin::InstallmentsController < ApplicationController
  def create
    @series_record = Record.active.series.find(params[:series_record_id])
    @book_record   = Record.active.books.find(params[:book_record_id])
    authorize_membership!(@series_record, @book_record)
    @context = params[:context]

    @installment = Installment.where(series_record_id: @series_record.id, book_record_id: @book_record.id)
      .first_or_create! do |installment|
        installment.position = (Installment.where(series_record_id: @series_record.id).maximum(:position) || 0) + 1
      end
  end

  def destroy
    @installment = Installment.find(params[:id])
    authorize_membership!(Record.find(@installment.series_record_id), Record.find(@installment.book_record_id))
    @installment.destroy
    render turbo_stream: turbo_stream.remove(helpers.dom_id(@installment))
  end

  private
    def authorize_membership!(series_record, book_record)
      return if allowed_to?(:manage, series_record) || allowed_to?(:manage, book_record)
      raise ApplicationPolicy::NotAuthorizedError
    end
end
