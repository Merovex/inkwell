# Resolves a comment's Record (:id is the Record id, never a version id), its
# current version, and the parent record it hangs from (the post's record).
module CommentScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.comments.find(params[:id])
      @comment = @record.recordable
      @parent = @record.parent
    end
end
