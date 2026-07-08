# Creates a comment under a message: originate a new Record parented to the
# message's record. Member actions (edit/update/destroy) are shallow — see
# CommentsController.
class Admin::Messages::CommentsController < ApplicationController
  include MessageScoped
  # Commenting follows visibility: you can't reply to a draft you can't see.
  before_action -> { authorize! @record, to: :view }

  # The composer, fetched into the message page's new_comment turbo frame
  # when the "Add your comment…" prompt is clicked.
  def new
  end

  def create
    @comment = Comment.new(comment_params)

    if @comment.valid?
      Record.originate(@comment, parent: @record)
      redirect_to admin_message_path(@record, anchor: "comment_#{@comment.record_id}")
    else
      redirect_to admin_message_path(@record, anchor: "new_comment"), alert: "Comment can't be blank."
    end
  end

  private
    def comment_params
      params.expect(comment: [ :content ])
    end
end
