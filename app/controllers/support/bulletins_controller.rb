# Authoring platform bulletins — root staff only, gated like the desk (bare
# 404 for everyone else). The composer mirrors posts: Publishable supplies
# the draft → scheduled → published ladder, the shared scheduler panel books
# the time, Record#save_edit folds edits into transitions. Bulletins
# originate with an explicit NIL bucket — platform content, never the
# request's account.
class Support::BulletinsController < ApplicationController
  include Publishing
  layout "application"

  require_root
  before_action :set_record, only: %i[edit update]

  def index
    Current.allowing_unscoped_tenancy do
      @bulletins = Bulletin.listed
        .includes(:body, record: { creator: { avatar_attachment: :blob } })
        .feed_ordered.to_a
    end
  end

  def new
    @bulletin = Bulletin.new
  end

  def create
    @bulletin = Bulletin.new(bulletin_params.merge(event: :created, status: initial_status,
      published_at: (Time.current if publishing?)))

    @bulletin.valid?
    # The model validates schedule times on the transition version; at create
    # the record doesn't exist yet, so pre-flight the check here (posts do the
    # same).
    if scheduling? && !scheduled_at&.future?
      @bulletin.errors.add(:base, "That scheduled time has already passed — pick a later one.")
    end

    if @bulletin.errors.none?
      Record.originate(@bulletin)
      @bulletin.schedule(at: scheduled_at) if scheduling?
      redirect_to support_bulletins_path,
        notice: publishing? ? "Bulletin published — every user gets a notification." : "Bulletin saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @bulletin = @record.save_edit(**bulletin_params.to_h.symbolize_keys,
      publish: publishing?, schedule_at: (scheduled_at if scheduling?), unschedule: unscheduling?)

    if @bulletin.errors.none?
      redirect_to support_bulletins_path
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_record
      Current.allowing_unscoped_tenancy do
        @record = Record.active.bulletins.find(params[:id])
        @bulletin = @record.recordable
      end
    end

    def bulletin_params
      params.expect(bulletin: %i[title content])
    end
end
