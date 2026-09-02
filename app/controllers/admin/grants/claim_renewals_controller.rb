# Staff-side "send me a new link" for one grant — POST mails that magnet's
# fresh claim link to its subscriber (readers lose the email and write in).
# Confirmed readers only: pending hasn't proved the address, and the
# suppressed states have their own recovery flow (Reactivation).
class Admin::Grants::ClaimRenewalsController < Admin::BaseController
  def create
    grant = Current.account.grants.find(params[:grant_id])
    subscriber = grant.subscriber

    if subscriber.confirmed?
      MagnetMailer.claim(grant).deliver_later
      redirect_to admin_subscribers_path(state: "confirmed"),
        notice: "Download link for #{grant.magnet.title} sent to #{subscriber.email_address}."
    else
      redirect_to admin_subscribers_path(state: subscriber.status),
        alert: "#{subscriber.email_address} isn't confirmed — download links only go to confirmed readers."
    end
  end
end
