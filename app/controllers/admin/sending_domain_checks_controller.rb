# The email twin of Admin::CustomDomainChecksController: the Email tab's
# "Waiting for DNS" badge re-runs the SES verification poll inline and the
# redirect reports the outcome.
class Admin::SendingDomainChecksController < Admin::BaseController
  def create
    SendingDomainStatusJob.perform_now(Current.account)
    connected = Current.account.sending_domains.connected
    if connected.any? && connected.where.not(status: "live").none?
      redirect_to admin_sending_domains_path, notice: "Your sending domain is verified."
    else
      redirect_to admin_sending_domains_path,
        notice: "Checked — still waiting for DNS. New records can take a few minutes to appear."
    end
  end
end
