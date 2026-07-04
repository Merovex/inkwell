# Publishing modeled as a resource: POST /forum/:id/publish posts the
# message, DELETE reverts it. Both are event versions on the history.
class Messages::PublishesController < ApplicationController
  include MessageScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @message.publish
    redirect_to message_path(@record), notice: "Message posted."
  end

  def destroy
    @message.unpublish
    redirect_to message_path(@record), notice: "Message reverted to a draft."
  end
end
