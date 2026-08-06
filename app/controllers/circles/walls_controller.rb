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
      scope = @circle.records.listed.messages.order(id: :desc)
        .includes(creator: { avatar_attachment: :blob })
      scope = scope.where(records: { id: ...params[:before_id].to_i }) if params[:before_id].present?

      page = scope.limit(PER_PAGE + 1).to_a
      @more = page.size > PER_PAGE
      @records = page.first(PER_PAGE)

      messages = Message.where(id: @records.map(&:recordable_id))
        .includes(body: :rich_text_content).index_by(&:id)
      @messages_by_record = @records.index_with { |record| messages[record.recordable_id] }

      ids = @records.map(&:id)
      @comment_counts = @circle.records.active.comments.where(parent_id: ids).group(:parent_id).count
      @boost_counts = Boost.where(record_id: ids).group(:record_id).count

      # The Commons wall affixes the platform's announcements — first page only.
      if @circle.commons? && params[:before_id].blank?
        Current.allowing_unscoped_tenancy do
          @bulletins = Bulletin.current.published.includes(:record).feed_ordered.limit(3).to_a
        end
      end
    end
  end
end
