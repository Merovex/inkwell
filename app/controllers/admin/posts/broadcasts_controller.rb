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
    elsif scheduling? && !send_at&.future?
      redirect_to admin_post_path(@record), alert: "That send time has already passed — pick a later one."
    elsif scheduling? && before_publication?
      redirect_to admin_post_path(@record),
        alert: "That's before the post publishes (#{@post.published_at.strftime('%b %-d at %-l:%M %p')}) — " \
               "pick a time after it, or the email would link to a post that isn't live yet."
    else
      deliver(@record.create_broadcast!(scheduled_at: (send_at if scheduling?)))
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

    # Emails book at half past the hour (the scheduler panel is rendered with
    # the same minute), so a send booked for the post's own publish hour lands
    # after the post is live rather than racing the site build.
    def send_at = scheduled_at(minute: 30)

    # A scheduled post's appointment is in published_at; booking the email
    # before it would mail a link to a post the static site doesn't carry yet.
    # Inert for an already-published post, whose published_at is in the past.
    def before_publication? = @post.published_at.present? && send_at < @post.published_at

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
