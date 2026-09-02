# Shallow member actions for a site-side comment (posts, forum). CommentScoped
# supplies the record + yours-only authorization; the CRUD shape lives in
# CommentActions.
class Admin::CommentsController < ApplicationController
  include CommentScoped
  include CommentActions
end
