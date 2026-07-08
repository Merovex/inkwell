# Shallow member actions for a comment. Edit and update swap within the
# comment's turbo frame on its parent's page (a post or a forum message);
# comments are never mutable, so every update lands as a tracked version.
class Admin::CommentsController < ApplicationController
  include CommentScoped

  def edit
  end

  def update
    @comment = @record.revise(event: :updated, **comment_params.to_h.symbolize_keys)

    if @comment.errors.none?
      redirect_to helpers.commentable_path(@parent, anchor: "comment_#{@record.id}")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Same trash ceremony as posts: an event on the history, recoverable
  # until purged.
  def destroy
    @record.trash
    redirect_to helpers.commentable_path(@parent), notice: "Comment moved to trash."
  end

  private
    def comment_params
      params.expect(comment: [ :content ])
    end
end
