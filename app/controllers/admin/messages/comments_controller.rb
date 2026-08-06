# Comments under a forum message. Scoping/authorization only — the CRUD shape
# lives in CommentActions; member actions are shallow, see
# Admin::CommentsController.
class Admin::Messages::CommentsController < ApplicationController
  include MessageScoped
  # Commenting follows visibility: you can't reply to a draft you can't see.
  before_action -> { authorize! @record, to: :view }
  before_action { @parent = @record }

  include CommentActions
end
