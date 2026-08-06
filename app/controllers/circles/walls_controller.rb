# The Wall — the circle's feed presentation candidate (2026-08-06): messages
# and pulse answers (Beats, wearing their question as the title) listed
# reverse-chrono, each at its own record id — one cursor, one feed; the tail
# is a lazy turbo-frame that loads the next page as it scrolls into view. On
# the Commons, published Bulletins affix above the stream. Cards
# fragment-cache.
module Circles
  class WallsController < BaseController
    PER_PAGE = 10

    def show
      before = params[:before_id].presence&.to_i

      messages = message_page(before)
      beats = beat_page(before)

      candidates =
        messages.first(PER_PAGE).map { |m| { anchor: m.record_id, message: m } } +
        beats.first(PER_PAGE).map { |b| { anchor: b.record_id, beat: b } }
      @items = candidates.sort_by { |item| -item[:anchor] }.first(PER_PAGE)
      @more = (messages.size + beats.size) > @items.size
      @cursor = @items.last&.dig(:anchor)

      prepare_messages(@items.filter_map { |i| i[:message] })
      prepare_beats(@items.filter_map { |i| i[:beat] })
      item_record_ids = @records_by_message.values.map(&:id) + @beat_records.keys
      @comment_counts = @circle.records.active.comments
        .where(parent_id: item_record_ids).group(:parent_id).count
      @boosts_by_record = Boost.where(record_id: item_record_ids)
        .includes(creator: { avatar_attachment: :blob }).group_by(&:record_id)

      # First page only: the Commons affixes the platform's announcements, and
      # every wall affixes YOUR items — an unanswered pulse ask on top (the
      # one actionable row), then the drafts pointer, then pending
      # appointments (soonest first).
      if before.nil?
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
      # The stream carries only what the circle can see: published messages.
      # Drafts stay in their authors' drawers; scheduled ones surface only to
      # their own author, in the strip.
      def message_page(before)
        scope = Message.current_in(@circle.records.listed).published
          .order(record_id: :desc).includes(body: :rich_text_content)
        scope = scope.where(record_id: ...before) if before
        scope.limit(PER_PAGE + 1).to_a
      end

      # Pulse answers, public from their first save — every one a wall story.
      def beat_page(before)
        scope = Beat.current_in(@circle.records.listed)
          .order(record_id: :desc).includes(:rich_text_content)
        scope = scope.where(record_id: ...before) if before
        scope.limit(PER_PAGE + 1).to_a
      end

      def prepare_messages(messages)
        records = Record.where(id: messages.map(&:record_id))
          .includes(:bucket, creator: { avatar_attachment: :blob }).index_by(&:id)
        @records_by_message = messages.index_with { |message| records[message.record_id] }
      end

      # A beat's card needs its record (answerer) and its pulse (the title).
      def prepare_beats(beats)
        @beat_records = Record.where(id: beats.map(&:record_id))
          .includes(creator: { avatar_attachment: :blob }).index_by(&:id)
        @pulse_records = Record.where(id: @beat_records.values.map(&:parent_id).uniq).index_by(&:id)
      end

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
