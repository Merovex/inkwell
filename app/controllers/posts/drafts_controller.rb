# Unpublished work: drafts and scheduled posts, most recently touched first.
class Posts::DraftsController < ApplicationController
  include PostScoped
  skip_before_action :set_record, only: :index

  def index
    @posts = Post.current.where.not(status: :published)
      .includes(:record, :creator, body: :rich_text_content).order(updated_at: :desc)
  end

  # Tossing a draft destroys it outright — the world never saw it, so there's
  # nothing to stage in the trash. But a reverted draft that was once live
  # carries legal exposure: it goes to the trash on the retention clock
  # instead (2 years, see Post#retention_period). Currently-published posts
  # are guarded out entirely (they trash via posts#destroy).
  def destroy
    if @post.published?
      redirect_to drafts_path, alert: "Published posts go to the trash, not the shredder."
    elsif @post.ever_published?
      @record.trash
      redirect_to drafts_path, notice: "Moved to the trash — once-published posts are retained."
    else
      @record.destroy
      redirect_to drafts_path, notice: "Draft deleted."
    end
  end
end
