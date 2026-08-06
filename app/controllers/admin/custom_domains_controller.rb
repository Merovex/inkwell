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

    # The status poll re-enqueues itself for only ~2.6h after connect; authors
    # publish DNS on their own clock, so a row can validate after the poll
    # dies and freeze at "verifying". The author checking this page is the
    # natural retry signal — restart the poll when the row's gone stale (the
    # job touches last_checked_at every pass, so this can't storm).
    def repoll_if_stale
      return unless @domains.any? { |d| d.verifying? && (d.last_checked_at.nil? || d.last_checked_at < 10.minutes.ago) }
      CustomDomainStatusJob.perform_later(Current.account)
    end
end
