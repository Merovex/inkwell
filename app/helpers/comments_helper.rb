# Comments hang off more than one parent type now (posts, forum messages).
# These resolve the parent's page and nested comment routes from the record's
# delegated type — recordable_name is "post" or "message" — so the comment
# partials and shallow controller actions stay parent-agnostic.
module CommentsHelper
  def commentable_path(record, **options)
    public_send(:"admin_#{record.recordable_name}_path", record, **options)
  end

  def commentable_url(record, **options)
    public_send(:"admin_#{record.recordable_name}_url", record, **options)
  end

  def commentable_comments_path(record)
    public_send(:"admin_#{record.recordable_name}_comments_path", record)
  end

  def new_commentable_comment_path(record)
    public_send(:"new_admin_#{record.recordable_name}_comment_path", record)
  end
end
