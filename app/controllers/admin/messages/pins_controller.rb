# Pinning as a resource: POST pins, DELETE unpins. Event versions, offered on
# posted messages (the menu only shows the control there).
class Admin::Messages::PinsController < Admin::BaseController
  include MessageScoped
  before_action -> { authorize! @record, to: :manage }

  def create
    @message.pin
    redirect_to admin_message_path(@record), notice: "Message pinned."
  end

  def destroy
    @message.unpin
    redirect_to admin_message_path(@record), notice: "Message unpinned."
  end
end
