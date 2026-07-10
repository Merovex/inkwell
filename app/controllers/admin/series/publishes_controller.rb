# Publishing a series as a resource: POST publishes, DELETE reverts to draft.
class Admin::Series::PublishesController < Admin::BaseController
  include SeriesScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @series.publish
    redirect_to admin_series_path(@record), notice: "Series published."
  end

  def destroy
    @series.unpublish
    redirect_to admin_series_path(@record), notice: "Series reverted to a draft."
  end
end
