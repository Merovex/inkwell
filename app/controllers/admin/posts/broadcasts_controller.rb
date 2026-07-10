# Emailing a post to subscribers, modeled as a resource: POST
# /posts/:id/broadcast sends (now, or scheduled for later — the same deferred-job
# behavior as a post's scheduled publish); DELETE cancels a scheduled send.
# One-time per post (the Broadcast's unique record_id is the guard) and only for
# a post that's live or scheduled — you don't email a draft. The send itself
# fans out in PostBroadcastJob.
class Admin::Posts::BroadcastsController < Admin::BaseController
  include PostScoped
  include Publishing  # reuses scheduling? + scheduled_at (the day/hour scheduler)
  before_action -> { authorize! @record, to: :manage }

  def create
    if !broadcastable?
      redirect_to admin_post_path(@record), alert: "Publish or schedule the post before emailing it."
    elsif @record.broadcast
      redirect_to admin_post_path(@record), alert: "This post has already been emailed to subscribers."
    elsif scheduling? && !scheduled_at&.future?
      redirect_to admin_post_path(@record), alert: "That send time has already passed — pick a later one."
    else
      deliver(@record.create_broadcast!(scheduled_at: (scheduled_at if scheduling?)))
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to admin_post_path(@record), alert: "This post has already been emailed to subscribers."
  end

  def destroy
    broadcast = @record.broadcast

    if broadcast.nil? || broadcast.sent?
      redirect_to admin_post_path(@record), alert: "There's no scheduled send to cancel."
    else
      broadcast.destroy
      redirect_to admin_post_path(@record), notice: "Scheduled email canceled."
    end
  end

  private
    def broadcastable?
      @post.published? || @post.scheduled?
    end

    # Immediate sends fire now; scheduled sends wait until their time (mirrors
    # Record::PublishLaterJob). Either way the Broadcast row already guards
    # against a second send.
    def deliver(broadcast)
      if broadcast.scheduled?
        PostBroadcastJob.set(wait_until: broadcast.scheduled_at).perform_later(broadcast)
        zone = Time.find_zone(params[:scheduled_posting_at_zone]) || Time.zone
        redirect_to admin_post_path(@record),
          notice: "Scheduled to email subscribers on #{broadcast.scheduled_at.in_time_zone(zone).strftime('%b %-d at %H:%M')}."
      else
        PostBroadcastJob.perform_later(broadcast)
        redirect_to admin_post_path(@record), notice: "Emailing this post to your subscribers…"
      end
    end
end
