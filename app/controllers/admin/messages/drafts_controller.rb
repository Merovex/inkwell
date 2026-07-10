# Unpublished forum work: drafts and scheduled messages, most recently
# touched first. Yours only — unpublished work stays between its creator
# and the admin, who sees everyone's.
class Admin::Messages::DraftsController < Admin::BaseController
  include MessageScoped
  skip_before_action :set_record, only: :index
  before_action -> { authorize! @record, to: :manage }, only: :destroy

  def index
    @messages = RecordPolicy.scope_for(Current.user, Message.current.where.not(status: :published))
      .includes(:record, :creator, :category, body: :rich_text_content).order(updated_at: :desc)
  end

  # Tossing a draft destroys it outright — the world never saw it, so there's
  # nothing to stage in the trash. But a reverted draft that was once live
  # carries legal exposure: it goes to the trash on the retention clock
  # instead (2 years, see Publishable#retention_period). Currently-posted
  # messages are guarded out entirely (they trash via messages#destroy).
  def destroy
    if @message.published?
      redirect_to admin_message_drafts_path, alert: "Posted messages go to the trash, not the shredder."
    elsif @message.ever_published?
      @record.trash
      redirect_to admin_message_drafts_path, notice: "Moved to the trash — once-posted messages are retained."
    else
      @record.destroy
      redirect_to admin_message_drafts_path, notice: "Draft deleted."
    end
  end
end
