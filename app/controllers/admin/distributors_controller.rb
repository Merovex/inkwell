# Store buy-links on a book or series, added/removed live from its page. Keyed
# by the target Record (books and series both live on the spine), so the same
# controller serves both. You may manage links if you can manage the record.
class Admin::DistributorsController < ApplicationController
  before_action :set_record

  def create
    @distributor = @record.distributors.create(url: params[:url])
    log_change(:link_added) if @distributor.persisted?
  end

  def destroy
    @distributor = @record.distributors.find(params[:id])
    @distributor.destroy
    log_change(:link_removed)
    render turbo_stream: turbo_stream.remove(helpers.dom_id(@distributor))
  end

  private
    def set_record
      @record = Record.active.find(params[:record_id] || Distributor.find(params[:id]).record_id)
      authorize! @record, to: :manage
    end

    # Record an event version so the link change shows in the change log — but
    # only for published records; drafts mutate in place and have no history.
    def log_change(event)
      @record.revise(event: event) if @record.recordable.try(:published?)
    end
end
