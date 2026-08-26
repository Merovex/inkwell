# Connect-your-domain, the admin side of the Cloudflare-for-SaaS onboarding
# (docs/custom-domain-onboarding.md). The heavy lifting — normalise, uniqueness
# gate, create custom hostnames, write KV, enqueue the poll — lives in
# DomainConnection; this just runs it and renders status + DNS instructions.
class Admin::CustomDomainsController < Admin::BaseController
  def index
    load_domains
    repoll_if_stale
  end

  def create
    result = DomainConnection.connect(account: Current.account, input: params[:hostname])
    if result.ok?
      redirect_to admin_custom_domains_path,
        notice: "Domain connected. Add the DNS records below to finish — we'll email you when it's live."
    else
      load_domains
      flash.now[:alert] = result.error
      render :index, status: :unprocessable_entity
    end
  end

  # One connection per account (the apex and its www); disconnecting removes the
  # whole set so a stray www can't keep resolving.
  def destroy
    domain = Current.account.custom_domains.find(params[:id])
    apex = domain.hostname.delete_prefix("www.")
    Current.account.custom_domains.connected
      .where(hostname: [ apex, "www.#{apex}" ]).find_each { |d| DomainConnection.disconnect(domain: d) }
    redirect_to admin_custom_domains_path, notice: "#{apex} disconnected."
  end

  private
    def load_domains
      @domains = Current.account.custom_domains.connected.order(canonical: :desc, hostname: :asc)
      @cname_target = Rails.configuration.x.cloudflare.cname_target
    end

    # The status poll's chain is finite; authors publish DNS on their own clock,
    # so a row can validate after the poll stops and freeze short of live. The
    # author opening this page is the natural retry signal — restart the poll
    # when a row's gone stale (the job touches last_checked_at every pass, so
    # this can't storm). Rows the chain gave up on (error) are included: that
    # status means "nothing is watching", which is precisely when a visit
    # should start watching again.
    def repoll_if_stale
      return unless @domains.any? { |d| CustomDomain::UNRESOLVED_STATUSES.include?(d.status) && stale?(d) }
      CustomDomainStatusJob.perform_later(Current.account)
    end

    def stale?(domain) = domain.last_checked_at.nil? || domain.last_checked_at < 10.minutes.ago
end
