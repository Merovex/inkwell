# Comments hang off more than one parent type (posts, forum messages) in more
# than one bucket (an account's admin, or a circle). These resolve the parent's
# page and the nested comment routes from the record's delegated type AND its
# bucket, so the comment partials and controllers stay parent- and bucket-
# agnostic. A circle parent routes to /circles/…; anything else to the admin.
module CommentsHelper
  def commentable_path(record, **options)
    if circle_bucket?(record)
      circle_parent_path(record, **options)
    else
      public_send(:"admin_#{record.recordable_name}_path", record, **options)
    end
  end

  def commentable_url(record, **options)
    if circle_bucket?(record)
      circle_parent_path(record, **options.merge(only_path: false))
    else
      public_send(:"admin_#{record.recordable_name}_url", record, **options)
    end
  end

  def commentable_comments_path(record)
    if circle_bucket?(record)
      circle_record_comments_path(record.bucket, record)
    else
      public_send(:"admin_#{record.recordable_name}_comments_path", record)
    end
  end

  def new_commentable_comment_path(record)
    if circle_bucket?(record)
      new_circle_record_comment_path(record.bucket, record)
    else
      public_send(:"new_admin_#{record.recordable_name}_comment_path", record)
    end
  end

  # A comment's own edit / member paths — bucket-aware the same way.
  def comment_edit_path(comment_record)
    if circle_bucket?(comment_record)
      edit_circle_comment_path(comment_record.bucket, comment_record)
    else
      edit_admin_comment_path(comment_record)
    end
  end

  def comment_member_path(comment_record)
    if circle_bucket?(comment_record)
      circle_comment_path(comment_record.bucket, comment_record)
    else
      admin_comment_path(comment_record)
    end
  end

  private
    def circle_bucket?(record) = record.bucket.is_a?(Circle)

    # A circle parent's show page. Only Message has one today; extend per type
    # as circle recordables gain their own pages.
    def circle_parent_path(record, **options)
      circle_message_path(record.bucket, record, **options)
    end
end
