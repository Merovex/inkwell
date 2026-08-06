# Comments under a post. Scoping/authorization only — the CRUD shape lives in
# CommentActions; member actions (edit/update/destroy) are shallow, see
# Admin::CommentsController.
class Admin::Posts::CommentsController < ApplicationController
  include PostScoped
  # Commenting follows visibility: you can't reply to a draft you can't see.
  before_action -> { authorize! @record, to: :view }
  before_action { @parent = @record }

  include CommentActions
end
