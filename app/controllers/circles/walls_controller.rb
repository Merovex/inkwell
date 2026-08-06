# The Wall — the circle's feed presentation candidate (2026-08-06): messages
# rendered full-bodied, newest first, a click away from their threads (no
# inline expansion); the tail is a lazy turbo-frame that loads the next page
# as it scrolls into view. On the Commons, published Bulletins affix above
# the stream. Cursor pagination (before_id on the records spine) stays stable
# as new messages land; the cards themselves fragment-cache.
module Circles
  class WallsController < BaseController
    PER_PAGE = 10

    def show
      # The stream carries only what the circle can see: published messages.
      # Drafts stay in their authors' drawers; scheduled ones surface only to
      # their own author, in the strip below. Cursor stays on record ids.
      scope = Message.current_in(@circle.records.listed).published
        .order(record_id: :desc).includes(body: :rich_text_content)
      scope = scope.where(record_id: ...params[:before_id].to_i) if params[:before_id].present?

      page = scope.limit(PER_PAGE + 1).to_a
      @more = page.size > PER_PAGE
      messages = page.first(PER_PAGE)

      records = Record.where(id: messages.map(&:record_id))
        .includes(:bucket, creator: { avatar_attachment: :blob }).index_by(&:id)
      @records = messages.map { |message| records[message.record_id] }
      @messages_by_record = @records.zip(messages).to_h

      ids = @records.map(&:id)
      @comment_counts = @circle.records.active.comments.where(parent_id: ids).group(:parent_id).count
      @boosts_by_record = Boost.where(record_id: ids)
        .includes(creator: { avatar_attachment: :blob }).group_by(&:record_id)

      # First page only: the Commons affixes the platform's announcements, and
      # every wall affixes YOUR items — an unanswered pulse ask on top (the
      # one actionable row), then the drafts pointer, then pending
      # appointments (soonest first).
      if params[:before_id].blank?
        @pending_pulse = pending_pulse
        @drafts_count = Message.current_in(@circle.records.listed).drafted
          .created_by(Current.user).count
        @scheduled = Message.current_in(@circle.records.listed).scheduled
          .created_by(Current.user).order(:published_at).to_a
        if @circle.commons?
          Current.allowing_unscoped_tenancy do
            @bulletins = Bulletin.current.published.includes(:record).feed_ordered.limit(3).to_a
          end
        end
      end
    end

    private
      # The circle's pulse, when its latest ask still awaits YOUR answer —
      # only if you're a respondent (the ask never reached anyone else).
      def pending_pulse
        record = @circle.records.active.where(recordable_type: "Pulse").last or return
        pulse = record.recordable
        return unless pulse.last_asked_on.present?
        return unless pulse.respondents.exists?(id: Current.user.id)
        return if pulse.beats_on(pulse.last_asked_on)
          .joins(:record).where(records: { creator_id: Current.user.id }).exists?
        pulse
      end
  end
end
