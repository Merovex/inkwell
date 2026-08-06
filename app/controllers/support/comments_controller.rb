# Comments on a support ticket — the thread between requester and staff.
# Scoping/authorization only: may comment = the requester (the ticket's
# bucket owner) or root staff; edit is the author's; trash is the author's or
# staff's. The CRUD shape lives in CommentActions; routes resolve through the
# bucket-aware CommentsHelper.
class Support::CommentsController < ApplicationController
  before_action :set_parent, only: %i[new create]
  before_action :set_comment, only: %i[edit update destroy]
  before_action :require_participant, only: %i[new create]
  before_action :require_author, only: %i[edit update]
  before_action :require_moderate, only: :destroy

  include CommentActions

  private
    def set_parent
      @parent = Current.allowing_unscoped_tenancy { Record.active.tickets.find(params[:ticket_id]) }
    end

    def set_comment
      @record = Current.allowing_unscoped_tenancy { Record.active.comments.find(params[:id]) }
      @comment = @record.recordable
      @parent = @record.parent
    end

    def participant?(record)
      Current.user&.root? || record.bucket == Current.user
    end

    def require_participant
      head :not_found unless participant?(@parent)
    end

    def require_author
      head :not_found unless @record.creator_id == Current.user&.id
    end

    def require_moderate
      head :not_found unless @record.creator_id == Current.user&.id || Current.user&.root?
    end
end
