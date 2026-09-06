# Attributing one reader to a promotion by hand, as a resource: POST attributes,
# DELETE undoes. The escape hatch for arrivals no token can name — a swap with
# no trackable link, or a reader who wrote in to say where they found you.
#
# Recording who did it is the point: Subscriber#attributed_by is nil for the
# ordinary matched attribution, so a promotion can always say how much of its
# number was measured and how much was asserted.
class Admin::Subscribers::AttributionsController < Admin::BaseController
  before_action :set_subscriber

  def create
    promotion = Current.account.promotions.find(params[:promotion_id])
    @subscriber.update!(promotion: promotion, attributed_by: Current.user)

    redirect_back_or_to admin_subscribers_path(state: @subscriber.status),
      notice: "#{@subscriber.email_address} attributed to #{promotion.title}."
  end

  def destroy
    @subscriber.update!(promotion: nil, attributed_by: nil)

    redirect_back_or_to admin_subscribers_path(state: @subscriber.status),
      notice: "#{@subscriber.email_address} is no longer attributed to a promotion."
  end

  private
    def set_subscriber
      @subscriber = Current.account.subscribers.find(params[:subscriber_id])
    end
end
