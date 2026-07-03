# Pinning as a resource: POST pins, DELETE unpins. Event versions, offered on
# published posts (the menu only shows the control there).
class Posts::PinsController < ApplicationController
  include PostScoped

  def create
    @post.pin
    redirect_to post_path(@record), notice: "Post pinned."
  end

  def destroy
    @post.unpin
    redirect_to post_path(@record), notice: "Post unpinned."
  end
end
