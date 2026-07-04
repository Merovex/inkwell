# The message board lives at /forum: index is the board itself (the one tool
# page for the install, like the chatroom), and everything else mirrors
# PostsController — messages share the whole publishable regime.
class MessagesController < ApplicationController
  include MessageScoped, Publishing
  skip_before_action :set_record, only: %i[index new create]
  before_action -> { authorize! @record, to: :view }, only: :show
  before_action -> { authorize! @record, to: :manage }, only: %i[edit update destroy]

  # The board: published messages, pinned first; unpublished work (drafts +
  # scheduled) lives behind the counted link to forum/drafts.
  def index
    @messages = Message.current.published
      .includes(:record, :creator, :category, body: :rich_text_content).feed_ordered

    @comment_counts = Record.active.comments
      .where(parent_id: @messages.map(&:record_id)).group(:parent_id).count

    unpublished = RecordPolicy.scope_for(Current.user, Message.current.where.not(status: :published))
      .group(:status).count
    @drafts_count = unpublished["drafted"].to_i
    @scheduled_count = unpublished["scheduled"].to_i
  end

  def show
  end

  def new
    @message = Message.new
  end

  def create
    @message = Message.new(message_params.merge(event: :created, status: initial_status,
      published_at: (Time.current if publishing?)))

    @message.valid?
    # The model validates schedule times on the transition version; at create
    # the record doesn't exist yet, so pre-flight the check here.
    if scheduling? && !scheduled_at&.future?
      @message.errors.add(:base, "That scheduled time has already passed — pick a later one.")
    end

    if @message.errors.none?
      Record.originate(@message)
      @message.schedule(at: scheduled_at) if scheduling?
      redirect_to message_path(@message.record), notice: create_notice
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
    @message = @record.save_edit(**message_params.to_h.symbolize_keys,
      publish: publishing?, schedule_at: (scheduled_at if scheduling?), unschedule: unscheduling?)

    if @message.errors.none?
      redirect_to message_path(@record)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Delete = trash the envelope (an event on the history, draft or published);
  # the message stays recoverable until purged.
  def destroy
    @record.trash
    redirect_to messages_path, notice: "Message moved to trash."
  end

  private
    def message_params
      params.expect(message: [ :title, :content, :category_id ])
    end

    def create_notice
      if scheduling?
        "Message scheduled for #{scheduled_at.strftime('%b %-d at %H:%M')}."
      elsif publishing?
        "Message posted."
      else
        "Draft saved."
      end
    end
end
