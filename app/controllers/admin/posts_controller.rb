class Admin::PostsController < ApplicationController
  include PostScoped, Publishing
  skip_before_action :set_record, only: %i[index new create]
  before_action -> { authorize! @record, to: :view }, only: :show
  before_action -> { authorize! @record, to: :manage }, only: %i[edit update destroy]

  # The default view is the published feed; unpublished work (drafts +
  # scheduled) lives behind the counted link to posts/drafts.
  def index
    @posts = Post.current.published
      .includes(:record, :creator, body: :rich_text_content).feed_ordered

    @comment_counts = Record.active.comments
      .where(parent_id: @posts.map(&:record_id)).group(:parent_id).count

    unpublished = RecordPolicy.scope_for(Current.user, Post.current.where.not(status: :published))
      .group(:status).count
    @drafts_count = unpublished["drafted"].to_i
    @scheduled_count = unpublished["scheduled"].to_i
  end

  def show
  end

  def new
    @post = Post.new
  end

  def create
    @post = Post.new(post_params.merge(event: :created, status: initial_status,
      published_at: (Time.current if publishing?)))

    @post.valid?
    # The model validates schedule times on the transition version; at create
    # the record doesn't exist yet, so pre-flight the check here.
    if scheduling? && !scheduled_at&.future?
      @post.errors.add(:base, "That scheduled time has already passed — pick a later one.")
    end

    if @post.errors.none?
      Record.originate(@post)
      @post.schedule(at: scheduled_at) if scheduling?
      redirect_to admin_post_path(@post.record), notice: create_notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Also hit by the show page's inline rename (title only). The whole save
  # policy — transitions and the drafts-mutate/published-version regime —
  # lives in Record#save_edit.
  def update
    @post = @record.save_edit(**post_params.to_h.symbolize_keys,
      publish: publishing?, schedule_at: (scheduled_at if scheduling?), unschedule: unscheduling?)

    if @post.errors.none?
      redirect_to admin_post_path(@record)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Delete = trash the envelope (an event on the history, draft or published);
  # the post stays recoverable until purged.
  def destroy
    @record.trash
    redirect_to admin_posts_path, notice: "Post moved to trash."
  end

  private
    def post_params
      params.expect(post: [ :title, :content, :excerpt, :author_record_id ])
    end

    def create_notice
      if scheduling?
        "Post scheduled for #{scheduled_at.strftime('%b %-d at %H:%M')}."
      elsif publishing?
        "Post published."
      else
        "Draft saved."
      end
    end
end
