# Publishing a collection as a resource: POST publishes, DELETE reverts to draft.
class Admin::Collections::PublishesController < Admin::BaseController
  include CollectionScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @collection.publish
    redirect_to admin_collection_path(@record), notice: "Collection published."
  end

  def destroy
    @collection.unpublish
    redirect_to admin_collection_path(@record), notice: "Collection reverted to a draft."
  end
end
