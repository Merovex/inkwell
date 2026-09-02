# The one implementation of comment CRUD, wherever comments hang — site posts,
# forum messages, circle records, support tickets. Including controllers own
# SCOPING and AUTHORIZATION (before_actions setting @parent for new/create,
# @record/@comment for member actions); this concern owns the shape:
# originate-under-parent, notifications, bucket-aware redirects
# (CommentsHelper), and the shared composer/edit templates (app/views/comments).
# Mentions no-op outside circle buckets, so they're safe to fire uniformly.
module CommentActions
  extend ActiveSupport::Concern

  # The composer, fetched into the parent page's new_comment turbo frame when
  # the "Add your comment…" prompt is clicked.
  def new
    render "comments/new"
  end

  def create
    @comment = Comment.new(comment_params)

    if @comment.valid?
      Record.originate(@comment, parent: @parent)
      Mentions.deliver_for(@comment.record)
      Replies.deliver_for(@comment.record)
      respond_to do |format|
        # Streams append the comment in place — the page's thread or the wall
        # modal — with no full re-render; the redirect is the no-JS fallback.
        format.turbo_stream { render "comments/create" }
        format.html { redirect_to after_comment_path }
      end
    else
      redirect_to helpers.commentable_path(@parent, anchor: "new_comment"), alert: "Comment can't be blank."
    end
  end

  def edit
    render "comments/edit"
  end

  def update
    @comment = @record.revise(event: :updated, **comment_params.to_h.symbolize_keys)

    if @comment.errors.none?
      Mentions.deliver_for(@record)
      redirect_to helpers.commentable_path(@parent, anchor: "comment_#{@record.id}")
    else
      render "comments/edit", status: :unprocessable_entity
    end
  end

  # Same trash ceremony as posts: an event on the history, recoverable
  # until purged.
  def destroy
    @record.trash
    redirect_to helpers.commentable_path(@parent), notice: "Comment moved to trash."
  end

  private
    def comment_params
      params.expect(comment: [ :content ])
    end

    # Where a saved comment lands the browser: the thread on the parent's
    # page. Contexts with their own thread surface (the Wall's modal)
    # override.
    def after_comment_path
      helpers.commentable_path(@parent, anchor: "comment_#{@comment.record_id}")
    end
end
