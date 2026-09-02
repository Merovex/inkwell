# Platform announcements, readable by any signed-in user (the bell links
# here). Bulletins are platform records — no bucket — so reads declare the
# deliberate cross-tenant sweep.
class BulletinsController < ApplicationController
  def index
    Current.allowing_unscoped_tenancy do
      @bulletins = Bulletin.current.published
        .includes(:body, record: { creator: { avatar_attachment: :blob } })
        .feed_ordered.to_a
    end
  end

  def show
    Current.allowing_unscoped_tenancy do
      @record = Record.active.bulletins.find(params[:id])
      @bulletin = @record.recordable
      # Drafts and scheduled bulletins are the staff's business until they land.
      head :not_found unless @bulletin.published? || Current.user&.root?
    end
  end
end
