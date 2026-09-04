# Sendy's /api/subscribers/active-subscriber-count.php — how many people are on
# the list. BookFunnel calls this (or its sibling) when you press Integrate, to
# check the host, key and list ID hang together; a failure here is the
# "We had trouble verifying your settings" message, not a subscribe problem.
#
# "Active" means what it means everywhere else in this app: confirmed, and a
# reader rather than a deliverability seed (Subscriber.sendable). A POST that
# only reads is Sendy's choice, not ours — hence show, behind their verb.
class Sendy::SubscriberCountsController < Sendy::BaseController
  MISSING_LIST = "List ID not passed"
  NO_SUCH_LIST = "List does not exist"

  def show
    return render_sendy(MISSING_LIST) if params[:list_id].blank?
    return render_sendy(NO_SUCH_LIST) unless names_the_account?(params[:list_id])

    count = Current.with_account(@account) { @account.subscribers.sendable.count }
    render_sendy(count.to_s)
  end
end
