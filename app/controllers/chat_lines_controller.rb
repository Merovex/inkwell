# Says a line in the room (create) or takes one back (destroy — the same
# trash ceremony as everything on the spine, recoverable until purged).
# A chat line's record has no parent: the install has a single room.
class ChatLinesController < ApplicationController
  def create
    @chat_line = ChatLine.new(chat_line_params)

    if @chat_line.valid?
      Record.originate(@chat_line)
      redirect_to chatroom_path(anchor: "chat_line_#{@chat_line.record_id}")
    else
      redirect_to chatroom_path, alert: "Say something first."
    end
  end

  # Only your own lines: scoping through the creator is the authorization,
  # so someone else's line 404s rather than 403s.
  def destroy
    @record = Record.active.chat_lines.where(creator: Current.user).find(params[:id])
    @record.trash
    redirect_to chatroom_path, notice: "Chat line moved to trash."
  end

  private
    def chat_line_params
      params.expect(chat_line: [ :content ])
    end
end
