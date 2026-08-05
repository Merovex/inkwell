# Comments on a circle's records — a discussion (Message) today, any commentable
# circle record tomorrow. Create nests under the parent record; member actions
# are keyed by the comment's own Record id. Authorization is bucket-agnostic:
# any member may comment, only the author may edit, and the author OR the circle
# owner may trash (the moderation override). Reuses the shared comment views via
# the bucket-aware CommentsHelper.
module Circles
  class CommentsController < BaseController
    before_action :set_parent, only: %i[new create]
    before_action :set_comment, only: %i[edit update destroy]
    before_action -> { authorize! @circle, to: :post }, only: :create
    before_action :require_edit, only: %i[edit update]
    before_action :require_moderate, only: :destroy

    def new
    end

    def create
      @comment = Comment.new(comment_params)

      if @comment.valid?
        Record.originate(@comment, parent: @parent)
        Mentions.deliver_for(@comment.record)
        redirect_to helpers.commentable_path(@parent, anchor: "comment_#{@comment.record_id}")
      else
        redirect_to helpers.commentable_path(@parent), alert: "Comment can't be blank."
      end
    end

    def edit
      render "admin/comments/edit"
    end

    def update
      @comment = @record.revise(event: :updated, **comment_params.to_h.symbolize_keys)

      if @comment.errors.none?
        Mentions.deliver_for(@record)
        redirect_to helpers.commentable_path(@record.parent, anchor: "comment_#{@record.id}")
      else
        render "admin/comments/edit", status: :unprocessable_entity
      end
    end

    def destroy
      @record.trash
      redirect_to helpers.commentable_path(@record.parent), notice: "Comment moved to trash."
    end

    private
      # The record being commented on — any live record in this circle.
      def set_parent
        @record = @parent = @circle.records.active.find(params[:record_id])
      end

      def set_comment
        @record = @circle.records.active.comments.find(params[:id])
        @comment = @record.recordable
        @parent = @record.parent
      end

      def require_edit
        raise ActiveRecord::RecordNotFound unless @record.editable_by?(Current.user)
      end

      def require_moderate
        raise ActiveRecord::RecordNotFound unless @record.moderatable_by?(Current.user)
      end

      def comment_params
        params.expect(comment: [ :content ])
      end
  end
end
