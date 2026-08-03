# Posting to a circle's board. Create is the only action for the stub: the
# message is originated on the spine with the circle as its bucket (set by the
# base controller), so it lives in the circle, never a site. Board posts are
# never mutable — an edit would land as a tracked version, like a chat line.
module Circles
  class MessagesController < BaseController
    def create
      authorize! @circle, to: :post

      @circle_message = CircleMessage.new(title: message_params[:title], content: formatted_content)

      if @circle_message.valid?
        Record.originate(@circle_message)
        redirect_to circle_path(@circle, anchor: "circle_message_#{@circle_message.record_id}")
      else
        redirect_to circle_path(@circle), alert: "Write something first."
      end
    end

    private
      def message_params
        params.expect(circle_message: [ :title, :content ])
      end

      # Board bodies are typed plain: escape, then honor the newlines the
      # composer put in (Action Text stores HTML, where a bare newline is a
      # space). Same treatment as chat lines.
      def formatted_content
        ERB::Util.html_escape(message_params[:content].to_s.strip).gsub(/\r?\n/, "<br>")
      end
  end
end
