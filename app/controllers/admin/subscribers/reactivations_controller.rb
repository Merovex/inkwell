# Lifts a delivery suppression from the roster (POST creates the reactivated
# state — see Subscriber#reactivate! for the bounced/complained split). The
# roster's Reactivate/Re-invite buttons land here.
class Admin::Subscribers::ReactivationsController < Admin::BaseController
  def create
    subscriber = Current.account.subscribers.find(params[:subscriber_id])
    was = subscriber.status

    if subscriber.reactivate!(ip: request.remote_ip)
      notice = was == "complained" ?
        "Re-invitation sent to #{subscriber.email_address} — they're back when they confirm." :
        "#{subscriber.email_address} reactivated."
      redirect_to admin_subscribers_path(state: subscriber.status), notice: notice
    else
      redirect_to admin_subscribers_path(state: was),
        alert: "#{subscriber.email_address} can't be reactivated from #{was}."
    end
  end
end
