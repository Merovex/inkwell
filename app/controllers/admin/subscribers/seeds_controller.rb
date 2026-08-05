# Deliverability-seed status as a resource: POST marks a subscriber as a seed
# inbox, DELETE returns them to a real reader — each request names its
# direction (no toggle races). For services whose inbox domains rotate per
# account (GlockApps, Everest) and so can't live in Subscriber::SEED_DOMAINS.
# A seed keeps its row and status but gets no broadcasts or drips and drops
# out of the roster counts.
class Admin::Subscribers::SeedsController < Admin::BaseController
  before_action :set_subscriber

  def create
    @subscriber.update!(seed: true)
    redirect_to admin_subscribers_path(state: @subscriber.status),
      notice: "#{@subscriber.email_address} marked as a seed."
  end

  def destroy
    @subscriber.update!(seed: false)
    redirect_to admin_subscribers_path(state: @subscriber.status),
      notice: "#{@subscriber.email_address} is no longer a seed."
  end

  private
    def set_subscriber
      @subscriber = Current.account.subscribers.find(params[:subscriber_id])
    end
end
