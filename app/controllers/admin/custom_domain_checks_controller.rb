# The "Waiting for DNS" badge's retry (shared/check_badge): create runs the
# status poll inline so the author gets an immediate answer — the background
# poll's re-enqueue chain dies ~2.6h after connect, but DNS lands on the
# author's clock.
class Admin::CustomDomainChecksController < Admin::BaseController
  def create
    CustomDomainStatusJob.perform_now(Current.account)
    connected = Current.account.custom_domains.connected
    if connected.any? && connected.where.not(status: "live").none?
      redirect_to admin_custom_domains_path, notice: "Your domain is live."
    else
      redirect_to admin_custom_domains_path,
        notice: "Checked — still waiting for DNS. New records can take a few minutes to appear."
    end
  end
end
