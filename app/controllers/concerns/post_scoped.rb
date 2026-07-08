# Resolves the Record (the public identity — /posts/:id is a Record id, never
# a version id) and its current version for all post-facing controllers.
module PostScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_record
  end

  private
    def set_record
      @record = Record.active.posts.find(params[:post_id] || params[:id])
      @post = @record.recordable
    end
end
