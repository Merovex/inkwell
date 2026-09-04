# Sendy's /api/subscribers/subscription-status.php — where does this address
# stand on the list? BookFunnel asks before letting a reader through a
# restricted download page, and to keep someone who unsubscribed from signing
# up again.
#
# Our statuses map onto Sendy's word-for-word except "Soft bounced", which we
# don't model: a soft bounce never changes a Subscriber's status here (only a
# hard one does), so no row can ever be in that state.
class Sendy::SubscriptionStatusesController < Sendy::BaseController
  MISSING_LIST  = "List ID not passed"
  NO_SUCH_LIST  = "List does not exist"
  MISSING_EMAIL = "Email not passed"
  NOT_ON_LIST   = "Email does not exist in list"

  STATUSES = {
    "confirmed" => "Subscribed",
    "pending" => "Unconfirmed",
    "unsubscribed" => "Unsubscribed",
    "bounced" => "Bounced",
    "complained" => "Complained"
  }.freeze

  def show
    return render_sendy(MISSING_EMAIL) if params[:email].blank?
    return render_sendy(MISSING_LIST) if params[:list_id].blank?
    return render_sendy(NO_SUCH_LIST) unless names_the_account?(params[:list_id])

    subscriber = Current.with_account(@account) do
      @account.subscribers.find_by(email_address: Subscriber.normalize_value_for(:email_address, params[:email]))
    end

    render_sendy(subscriber ? STATUSES.fetch(subscriber.status) : NOT_ON_LIST)
  end
end
