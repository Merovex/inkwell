# Publishing modeled as a resource: POST /posts/:id/publish publishes,
# DELETE unpublishes. Both are event versions on the history.
class Admin::Posts::PublishesController < Admin::BaseController
  include PostScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @post.publish
    redirect_to admin_post_path(@record), notice: "Post published."
  end

  def destroy
    booked_email = @record.broadcast&.scheduled?
    @post.unpublish

    notice = "Post reverted to a draft."
    notice += " The scheduled email was cleared too." if booked_email && @record.reload.broadcast.nil?
    redirect_to admin_post_path(@record), notice: notice
  end
end
