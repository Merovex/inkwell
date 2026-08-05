# A circle's discussions. Each one is a Message (the same class the site forum
# uses) whose Record carries the circle as its bucket, so it lives in the
# circle, never a site. Publishable exactly like the forum — post now, save a
# draft, or schedule for later. After creation the circle owner or the message's
# author may edit, archive, or trash it; a draft/scheduled discussion is visible
# only to those two.
module Circles
  class MessagesController < BaseController
    include Publishing

    before_action :set_message, only: %i[show edit update destroy archive unarchive]
    # Editing the words is the author's alone; moderating (archive, trash) is the
    # author or the circle owner.
    before_action -> { require_edit }, only: %i[edit update]
    before_action -> { require_moderate }, only: %i[destroy archive unarchive]

    helper_method :editable?, :moderatable?

    # The discussions this member may see (published to all; drafts/scheduled to
    # their author and the circle owner), newest first — the full list behind the
    # circle home's five-item preview. Scheduled and archived counts drive the
    # simple filter links below the header.
    def index
      visible = @circle.discussions_visible_to(Current.user)
      @scheduled_count = visible.where(status: :scheduled).count
      @archived_count = @circle.discussions_visible_to(Current.user, scope: @circle.archived_messages).count
      # The main list is posted-or-in-progress; scheduled ones wait in their own
      # view (a queued post isn't part of the conversation yet).
      @discussions = params[:scheduled] ? visible.where(status: :scheduled) : visible.where.not(status: :scheduled)
    end

    # The set-aside discussions, same visibility rules.
    def archived
      @discussions = @circle.discussions_visible_to(Current.user, scope: @circle.archived_messages)
    end

    def show
    end

    def new
      @message = Message.new
    end

    # Post now, save a draft, or schedule — the same ladder as the forum's
    # Admin::MessagesController#create, minus categories.
    def create
      authorize! @circle, to: :post

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
        redirect_to circle_message_path(@circle, @message.record), notice: create_notice
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    # The whole save policy — transitions and the drafts-mutate/published-version
    # regime — lives in Record#save_edit, same as the forum.
    def update
      @message = @record.save_edit(**message_params.to_h.symbolize_keys,
        publish: publishing?, schedule_at: (scheduled_at if scheduling?), unschedule: unscheduling?)

      if @message.errors.none?
        redirect_to circle_message_path(@circle, @record)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @record.trash
      redirect_to circle_messages_path(@circle), notice: "Discussion moved to trash."
    end

    def archive
      @record.archive
      redirect_to circle_message_path(@circle, @record), notice: "Discussion archived."
    end

    def unarchive
      @record.unarchive
      redirect_to circle_message_path(@circle, @record), notice: "Discussion restored."
    end

    private
      def set_message
        @record = @circle.records.active.messages.find(params[:id])
        @message = @record.recordable
      end

      # Anyone not permitted gets the same 404 as a missing record — what exists
      # is nobody else's business.
      def require_edit
        raise ActiveRecord::RecordNotFound unless editable?
      end

      def require_moderate
        raise ActiveRecord::RecordNotFound unless moderatable?
      end

      def editable?(record = @record) = record.editable_by?(Current.user)
      def moderatable?(record = @record) = record.moderatable_by?(Current.user)

      def message_params
        params.expect(message: [ :title, :content ])
      end

      def create_notice
        if scheduling? then "Scheduled to post to the circle."
        elsif publishing? then "Posted to the circle."
        else "Saved as a draft."
        end
      end
  end
end
