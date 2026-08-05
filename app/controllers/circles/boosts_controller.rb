# Boosts inside a circle — the same tiny appreciations as the admin side,
# scoped to the circle's records. Any member may cheer (post?); removing is
# only ever your own. Boosting also rings the author's bell (bell-only kind).
module Circles
  class BoostsController < BaseController
    before_action -> { authorize! @circle, to: :post }, only: :create

    def create
      record = @circle.records.active.find(params[:record_id])
      boost = record.boosts.create(boost_params)

      if boost.persisted? && record.creator_id != Current.user.id
        Notification.deliver(boost, to: record.creator, kind: "boosted")
      end

      redirect_to record_page_path(record)
    end

    def destroy
      boost = Current.user.boosts.find(params[:id])
      record = boost.record
      # The nested route claims this circle; a boost from elsewhere 404s.
      raise ActiveRecord::RecordNotFound unless record.bucket == @circle

      boost.destroy
      redirect_to record_page_path(record)
    end

    private
      def boost_params
        params.expect(boost: [ :content ])
      end
  end
end
