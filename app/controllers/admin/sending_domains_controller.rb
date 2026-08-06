# Connect-your-sending-domain, the Email tab of System settings — the email
# twin of Admin::CustomDomainsController. The heavy lifting — validate,
# uniqueness gate, create the SES identity, associate the tenant, enqueue the
# poll — lives in EmailConnection; this just runs it and renders status + DNS
# instructions.
class Admin::SendingDomainsController < Admin::BaseController
  def index
    load_domains
    repoll_if_stale
  end

  def create
    result = EmailConnection.connect(account: Current.account, input: params[:domain])
    if result.ok?
      redirect_to admin_sending_domains_path,
        notice: "Domain connected. Add the DNS records below to finish — we'll email you when it's verified."
    else
      load_domains
      flash.now[:alert] = result.error
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    domain = Current.account.sending_domains.find(params[:id])
    result = EmailConnection.disconnect(sending_domain: domain)
    if result.ok?
      redirect_to admin_sending_domains_path, notice: "#{domain.domain} disconnected — back to the shared sending address."
    else
      redirect_to admin_sending_domains_path, alert: result.error
    end
  end

  private
    def load_domains
      @domains = Current.account.sending_domains.connected.order(:domain)
    end

    # Same revival as Admin::CustomDomainsController#repoll_if_stale: the poll
    # dies ~2.6h after connect, DNS lands on the author's clock, and this page
    # is where they come to check.
    def repoll_if_stale
      return unless @domains.any? { |d| d.verifying? && (d.last_checked_at.nil? || d.last_checked_at < 10.minutes.ago) }
      SendingDomainStatusJob.perform_later(Current.account)
    end
end
