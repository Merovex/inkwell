# Staff-side "send them the book" for one (subscriber, magnet) pair — POST
# mints the Grant if the reader never held one (the magnet postdates their
# signup), renews the allowance, and mails a fresh claim link. Confirmed
# readers only: pending hasn't proved the address, and the suppressed states
# have their own recovery flow (Reactivation).
class Admin::Subscribers::Magnets::ClaimRenewalsController < Admin::BaseController
  def create
    subscriber = Current.account.subscribers.find(params[:subscriber_id])
    magnet = Current.account.magnets.find(params[:magnet_id])

    if subscriber.confirmed?
      grant = magnet.grant_to(subscriber)
      grant.renew
      MagnetMailer.claim(grant).deliver_later
      redirect_to admin_subscribers_path(state: "confirmed"),
        notice: "Download link for #{magnet.title} sent to #{subscriber.email_address}."
    else
      redirect_to admin_subscribers_path(state: subscriber.status),
        alert: "#{subscriber.email_address} isn't confirmed — download links only go to confirmed readers."
    end
  end
end
