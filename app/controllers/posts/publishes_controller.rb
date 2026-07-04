# Publishing modeled as a resource: POST /posts/:id/publish publishes,
# DELETE unpublishes. Both are event versions on the history.
class Posts::PublishesController < ApplicationController
  include PostScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @post.publish
    redirect_to post_path(@record), notice: "Post published."
  end

  def destroy
    @post.unpublish
    redirect_to post_path(@record), notice: "Post reverted to a draft."
  end
end
