# Pinning as a resource: POST pins, DELETE unpins. Event versions, offered on
# published posts (the menu only shows the control there).
class Admin::Posts::PinsController < ApplicationController
  include PostScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @post.pin
    redirect_to admin_post_path(@record), notice: "Post pinned."
  end

  def destroy
    @post.unpin
    redirect_to admin_post_path(@record), notice: "Post unpinned."
  end
end
