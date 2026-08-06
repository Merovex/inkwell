# Comments on a circle's records — a discussion (Message) today, any commentable
# circle record tomorrow. Scoping/authorization only: any member may comment,
# only the author may edit, the author OR the circle owner may trash (the
# moderation override). The CRUD shape lives in CommentActions; routes resolve
# through the bucket-aware CommentsHelper.
module Circles
  class CommentsController < BaseController
    before_action :set_parent, only: %i[new create]
    before_action :set_comment, only: %i[edit update destroy]
    before_action -> { authorize! @circle, to: :post }, only: :create
    before_action :require_edit, only: %i[edit update]
    before_action :require_moderate, only: :destroy

    include CommentActions

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

      # The Wall's thread modal posts with back=wall: the saved comment lands
      # back in the modal (its frame follows this redirect), not on the
      # message page.
      def after_comment_path
        return super unless params[:back] == "wall"
        circle_wall_thread_path(@circle, @parent)
      end
  end
end
