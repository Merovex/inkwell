# Resolves a comment's Record (:id is the Record id, never a version id), its
# current version, and the parent record it hangs from (the record it
# comments on). Member actions are yours-only, like chat lines: creator
# scoping is the authorization, so someone else's comment 404s rather
# than 403s.
module CommentScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.comments.where(creator: Current.user).find(params[:id])
      @comment = @record.recordable
      @parent = @record.parent
    end
end
