# The single chatroom. Show is the transcript plus the composer; there is
# nothing else to it — lines have their own controller.
class ChatroomsController < ApplicationController
  def show
    @chat_lines = ChatLine.transcript
  end
end
